# Copyright (c) 2018-2020 Zold
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the 'Software'), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED 'AS IS', WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

require 'time'
require 'zold/http'
require 'zold/amount'
require 'zold/id'
require 'zold/age'
require 'zold/json_page'
require_relative 'user_error'

# Payables.
# Author:: Yegor Bugayenko (yegor256@gmail.com)
# Copyright:: Copyright (c) 2018 Yegor Bugayenko
# License:: MIT
class WTS::Payables
  def initialize(pgsql, remotes, log: Zold::Log::NULL)
    @pgsql = pgsql
    @remotes = remotes
    @log = log
  end

  # Discover
  def discover
    start = Time.now
    seen = []
    total = 0
    @remotes.iterate(@log) do |r|
      next unless r.master?
      seen << r.to_s
      res = r.http('/wallets').get(timeout: 60)
      r.assert_code(200, res)
      ids = res.body.strip.split("\n").compact.select { |i| /^[a-f0-9]{16}$/.match?(i) }
      ids.each do |id|
        @pgsql.exec(
          'INSERT INTO payable (id, node) VALUES ($1, $2) ON CONFLICT (id) DO NOTHING',
          [id, r.to_mnemo]
        )
      end
      total += ids.count
      @log.debug("Payables: #{ids.count} wallets found at #{r} in #{Zold::Age.new(start)}")
    end
    @log.debug("Payables: #{seen.count} master nodes checked, #{total} wallets found: #{seen.join(', ')}")
  end

  # Fetch some balances
  def update(max: 400)
    if @remotes.all.empty?
      @log.debug('The list of remote nodes is empty, can\'t update payables')
      return
    end
    start = Time.now
    selected = 0
    ids = Queue.new
    @pgsql.exec('SELECT id FROM payable ORDER BY updated ASC LIMIT $1', [max]).each do |r|
      ids << r['id']
      selected += 1
    end
    total = 0
    seen = []
    @remotes.iterate(@log) do |r|
      next unless r.master?
      seen << r.to_s
      loop do
        id = nil
        begin
          id = ids.pop(true)
        rescue ThreadError
          break
        end
        res = r.http("/wallet/#{id}").get
        next unless res.status == 200
        json = Zold::JsonPage.new(res.body).to_hash
        @pgsql.exec(
          'UPDATE payable SET balance = $2, txns = $3, node = $4, updated = NOW() WHERE id = $1',
          [id, json['balance'], json['txns'], r.to_mnemo]
        )
        total += 1
      end
    end
    if total < max
      @log.error("For some reason not enough wallet balances were updated, \
just #{total} instead of #{max}, while #{selected} were selected and there were \
#{seen.count} master nodes seen: #{seen.join(', ')}")
    else
      @log.debug("Payables: #{total} wallet balances updated from #{seen.count} remote master \
in #{Zold::Age.new(start)}: #{seen.join(', ')}")
    end
  end

  # Remove old wallets
  def remove_old
    @pgsql.exec('DELETE FROM payable WHERE updated < NOW() - INTERVAL \'24 HOURS\'')
  end

  # Remove those, which are banned.
  def remove_banned
    Zold::Id::BANNED.each do |id|
      @pgsql.exec('DELETE FROM payable WHERE id = $1', [id])
    end
  end

  def fetch(max: 50)
    items = @pgsql.exec(
      [
        'SELECT payable.*, item.login AS login FROM payable',
        'LEFT JOIN item ON item.id = payable.id',
        'ORDER BY ABS(balance) DESC LIMIT $1'
      ].join(' '),
      [max]
    )
    items.map do |r|
      {
        id: Zold::Id.new(r['id']),
        login: r['login'],
        balance: Zold::Amount.new(zents: r['balance'].to_i),
        txns: r['txns'].to_i,
        updated: Time.parse(r['updated']),
        node: r['node']
      }
    end
  end

  # Total visible balance
  def balance
    Zold::Amount.new(zents: @pgsql.exec('SELECT SUM(balance) FROM payable WHERE balance > 0')[0]['sum'].to_i)
  end

  # Total visible wallets.
  def total
    @pgsql.exec('SELECT COUNT(*) FROM payable')[0]['count'].to_i
  end

  # Total visible transactions.
  def txns
    @pgsql.exec('SELECT SUM(txns) FROM payable')[0]['sum'].to_i
  end
end
