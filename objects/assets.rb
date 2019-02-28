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

require 'zold/log'
require_relative 'pgsql'
require_relative 'user_error'

# Bitcoin assets.
# Author:: Yegor Bugayenko (yegor256@gmail.com)
# Copyright:: Copyright (c) 2018 Yegor Bugayenko
# License:: MIT
class Assets
  def initialize(pgsql, log: Log::NULL)
    @pgsql = pgsql
    @log = log
  end

  def all
    @pgsql.exec('SELECT * FROM asset').map do |r|
      {
        hash: r['hash'],
        amount: r['satoshi'].to_i,
        updated: Time.parse(r['updated'])
      }
    end
  end

  # Get BTC balance, in BTC
  def balance
    @pgsql.exec('SELECT satoshi FROM asset').map { |r| r['satoshi'].to_i }.inject(&:+) / 100_000_000
  end

  # Add new asset.
  def add(hash, satoshi, pvt)
    @pgsql.exec('INSERT INTO asset (hash, satoshi, pvt) VALUES ($1, $2, $3)', [hash, satoshi, pvt])
  end

  # Prepare a batch to send.
  def prepare(satoshi)
    batch = []
    left = satoshi
    rows = @pgsql.exec('SELECT * FROM asset ORDER BY satoshi')
    while left > 0
      raise "Can't find enough satoshi to send #{satoshi}" if rows.empty?
      row = rows.shift
      batch << { hash: row['hash'], satoshi: row['satoshi'].to_i, pvt: row['pvt'] }
      left -= row['satoshi'].to_i
    end
    batch
  end

  # Mark this batch as sent (hash with {hashes => satoshi})
  def spent(batch)
    @pgsql.connect do |c|
      c.transaction do |con|
        batch.each do |p|
          con.exec(
            'UPDATE asset SET satoshi = satoshi - $1, updated = NOW() WHERE hash = $2',
            [p[:satoshi], p[:hash]]
          )
        end
        con.exec_params('DELETE FROM asset WHERE satoshi <= 0')
      end
    end
  end
end
