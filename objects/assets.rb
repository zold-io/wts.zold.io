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
require 'sibit'
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
    @sibit = Sibit.new(log: @log)
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

  # This address has an owner?
  def owned?(address)
    !@pgsql.exec('SELECT * FROM asset WHERE address = $1 AND login IS NOT NULL', [address]).empty?
  end

  # Current price of BTC in USD.
  def price
    @sibit.price
  end

  # Get total BTC balance, in BTC.
  def balance
    @pgsql.exec('SELECT SUM(value) FROM asset')[0]['sum'].to_f / 100_000_000
  end

  # Create a new asset/address for a given user (return existing one if it is
  # already in the database).
  def acquire(login = nil)
    row = if login.nil?
      @pgsql.exec('SELECT address FROM asset WHERE login IS NULL')[0]
    else
      @pgsql.exec('SELECT address FROM asset WHERE login = $1', [login])[0]
    end
    if row.nil?
      sibit = Sibit.new(log: @log)
      pvt = sibit.generate
      address = sibit.create(pvt)
      @pgsql.exec('INSERT INTO asset (address, login, pvt) VALUES ($1, $2, $3)', [address, login, pvt])
      @log.info("Bitcoin address #{address} acquired by #{login.inspect}")
      address
    else
      row['address']
    end
  end

  # Set the balance of an assert.
  def set(address, value)
    @pgsql.exec('UPDATE asset SET value = $1, updated = NOW() WHERE address = $2', [value, address])
  end

  # Get the latest block from the blockchain, scan all transactions visible
  # there and find those, which we are waiting for. Then, yield them one
  # by one if they haven't been seen yet in UTXOs.
  def monitor(seen, max: 1)
    ours = Set.new(all.map { |a| a[:address] })
    block = start = @sibit.latest
    count = 0
    while block != seen && count < max
      json = @sibit.get_json("/rawblock/#{block}")
      json['tx'].each do |t|
        t['out'].each do |o|
          next if o['spent']
          address = o['addr']
          next if address.nil?
          next unless ours.include?(address)
          next unless owned?(address)
          hash = "#{t['hash']}:#{o['n']}"
          next if seen?(hash)
          set(address, @sibit.balance(address))
          satoshi = o['value']
          yield(address, hash, satoshi)
          @log.info("Tx found at #{hash} for #{satoshi}s sent to #{address}")
        end
      end
      block = json['prev_block']
      count += 1
    end
    start
  end

  # Send a payment to the address.
  def pay(address, satoshi)
    batch = {}
    unspent = 0
    @pgsql.exec('SELECT address, pvt, value FROM asset WHERE value > 0 ORDER BY value').each do |r|
      batch[r['address']] = r['pvt']
      unspent += r['value'].to_i
      break if unspent > satoshi
    end
    raise "Not enough funds to send #{satoshi}, only #{unspent} left" if unspent < satoshi
    txn = @sibit.pay(satoshi, 'M', batch, address, acquire)
    batch.keys.each { |a| set(a, 0) }
    txn
  end

  def seen?(hash)
    !@pgsql.exec('SELECT * FROM utxo WHERE hash = $1', [hash]).empty?
  end

  # This UTXO has been seen, for the provided Bitcoin address.
  def see(address, hash)
    @pgsql.exec('INSERT INTO utxo (address, hash) VALUES ($1, $2)', [address, hash])
  end
end
