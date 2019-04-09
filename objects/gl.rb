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
require 'zold/txn'
require 'zold/id'
require 'zold/amount'
require 'zold/json_page'
require_relative 'pgsql'

# General ledger.
# Author:: Yegor Bugayenko (yegor256@gmail.com)
# Copyright:: Copyright (c) 2018 Yegor Bugayenko
# License:: MIT
class WTS::Gl
  def initialize(pgsql, log: Zold::Log::NULL)
    @pgsql = pgsql
    @log = log
  end

  def scan(remotes)
    remotes.iterate(@log) do |r|
      uri = '/ledger.json'
      res = r.http(uri).get
      r.assert_code(200, res)
      Zold::JsonPage.new(res.body, uri).to_hash.each do |t|
        row = @pgsql.exec(
          [
            'INSERT INTO txn (id, source, date, amount, target, prefix, details)',
            'VALUES ($1, $2, $3, $4, $5, $6, $7)',
            'ON CONFLICT DO NOTHING',
            'RETURNING *'
          ].join(' '),
          [
            t['id'],
            Zold::Id.new(t['source']).to_s,
            Zold::Txn.parse_time(t['date']).utc.iso8601,
            Zold::Amount.new(zents: t['amount'].to_i).to_i,
            Zold::Id.new(t['target']),
            t['prefix'],
            t['details']
          ]
        )
        yield map(row[0]) if !row.empty? && block_given?
      end
    end
  end

  def fetch(since: Time.now, limit: 50, query: '')
    raise 'Since has to be of time Time' unless since.is_a?(Time)
    q = [
      'SELECT * FROM txn WHERE date <= $1',
      'AND ($3 = \'\' OR source = $3 OR target = $3 OR details LIKE $3)',
      'ORDER BY date DESC LIMIT $2'
    ].join(' ')
    @pgsql.exec(q, [since.utc.iso8601, limit, query]).map do |r|
      map(r)
    end
  end

  def volume(hours = 24)
    Zold::Amount.new(
      zents: @pgsql.exec(
        "SELECT SUM(amount) FROM txn WHERE date > NOW() - INTERVAL \'#{hours} HOURS\'"
      )[0]['sum'].to_i
    )
  end

  def count(hours = 24)
    @pgsql.exec(
      "SELECT COUNT(*) FROM txn WHERE date > NOW() - INTERVAL \'#{hours} HOURS\'"
    )[0]['count'].to_i
  end

  def txn(source, id)
    row = @pgsql.exec('SELECT * FROM txn WHERE source = $1 AND id = $2', [source, id])[0]
    raise WTS::UserError, "192: Transaction #{source}:#{id} not found in GL" if row.nil?
    map(row)
  end

  private

  def map(r)
    {
      tid: "#{Zold::Id.new(r['source'])}:#{r['id'].to_i}",
      id: r['id'].to_i,
      date: Time.parse(r['date']),
      source: Zold::Id.new(r['source']),
      target: Zold::Id.new(r['target']),
      amount: Zold::Amount.new(zents: r['amount'].to_i),
      zents: r['amount'].to_i,
      prefix: r['prefix'],
      details: r['details']
    }
  end
end
