# Copyright (c) 2018-2019 Zerocracy, Inc.
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
require_relative 'pgsql'
require_relative 'user_error'

# Payables.
# Author:: Yegor Bugayenko (yegor256@gmail.com)
# Copyright:: Copyright (c) 2018 Yegor Bugayenko
# License:: MIT
class Payables
  def initialize(pgsql, remotes, log: Log::NULL)
    @pgsql = pgsql
    @remotes = remotes
    @log = log
  end

  # Discover
  def discover
    start = Time.now
    @remotes.iterate(@log) do |r|
      next unless r.master?
      res = r.http('/wallets').get
      r.assert_code(200, res)
      ids = res.body.strip.split("\n").compact.select { |i| /^[a-f0-9]{16}$/.match?(i) }
      ids.each do |id|
        @pgsql.exec(
          'INSERT INTO payable (id, node) VALUES ($1, $2) ON CONFLICT (id) DO NOTHING',
          [id, r.to_mnemo]
        )
      end
      @log.info("Payables: #{ids.count} wallets found at #{r} in #{Zold::Age.new(start)}")
    end
  end

  # Fetch some balances
  def update(max: 100)
    start = Time.now
    ids = Queue.new
    @pgsql.exec('SELECT id FROM payable ORDER BY updated LIMIT $1', [max]).map { |r| r['id'] }.take(max).each do |id|
      ids << id
    end
    total = 0
    @remotes.iterate(@log) do |r|
      next unless r.master?
      loop do
        id = nil
        begin
          id = ids.pop(true)
        rescue ThreadError
          break
        end
        res = r.http("/wallet/#{id}/balance").get
        r.assert_code(200, res)
        @pgsql.exec(
          'UPDATE payable SET balance = $2, updated = NOW() WHERE id = $1',
          [id, res.body.to_i]
        )
        total += 1
      end
    end
    @log.info("Payables: #{total} wallet balances updated in #{Zold::Age.new(start)}")
  end

  def fetch(max: 100)
    @pgsql.exec('SELECT * FROM payable ORDER BY balance DESC LIMIT $1', [max]).map do |r|
      {
        id: Zold::Id.new(r['id']),
        balance: Zold::Amount.new(zents: r['balance'].to_i),
        updated: Time.parse(r['updated']),
        node: r['node']
      }
    end
  end
end
