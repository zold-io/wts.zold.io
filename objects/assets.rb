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
require_relative 'wts'
require_relative 'pgsql'
require_relative 'user_error'

# Bitcoin assets.
# Author:: Yegor Bugayenko (yegor256@gmail.com)
# Copyright:: Copyright (c) 2018 Yegor Bugayenko
# License:: MIT
class WTS::Assets
  def initialize(pgsql, log: Zold::Log::NULL)
    @pgsql = pgsql
    @log = log
  end

  def all
    @pgsql.exec('SELECT * FROM asset').map do |r|
      {
        address: r['address'],
        login: r['login'],
        value: r['value'].to_i,
        updated: Time.parse(r['updated']),
        hot: !r['pvt'].nil?
      }
    end
  end

  # Get owner of the address.
  def owner(address)
    row = @pgsql.exec('SELECT login FROM asset WHERE address = $1', [address])[0]
    raise WTS::UserError, "197: The owner of #{address} not found" if row.nil?
    row['login']
  end

  # Get total BTC balance, in BTC.
  def balance
    @pgsql.exec('SELECT SUM(value) FROM asset')[0]['sum'].to_i / 100_000_000
  end

  # Create a new asset/address for a given user (return existing one if it is
  # already in the database).
  def acquire(login)
    row = @pgsql.exec('SELECT address FROM asset WHERE login = $1', [login])[0]
    if row.nil?
      sibit = Sibit.new(log: @log)
      pvt = sibit.generate
      address = sibit.create(pvt)
      @pgsql.exec('INSERT INTO asset (address, login, pvt) VALUES ($1, $2, $3)', [address, login, pvt])
      address
    else
      row['address']
    end
  end

  # Set the balance of an assert.
  def set(address, value)
    @pgsql.exec('UPDATE asset SET value = $1 WHERE address = $2', [value, address])
  end

  # Send a payment to the address.
  def send(btc, address, satoshi)
    batch = []
    left = satoshi
    rows = @pgsql.exec('SELECT * FROM asset ORDER BY satoshi')
    while left.positive?
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
