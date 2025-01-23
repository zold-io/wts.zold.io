# Copyright (c) 2018-2025 Zerocracy
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
require 'glogin'
require 'retriable'
require_relative 'wts'
require_relative 'user_error'

# Bitcoin assets.
# Author:: Yegor Bugayenko (yegor256@gmail.com)
# Copyright:: Copyright (c) 2018 Yegor Bugayenko
# License:: MIT
class WTS::Assets
  def initialize(pgsql, log: Zold::Log::NULL, sibit: Sibit.new(log: @log), codec: GLogin::Codec.new)
    @pgsql = pgsql
    @log = log
    @sibit = sibit
    @codec = codec
  end

  def all(show_empty: false)
    @pgsql.exec('SELECT * FROM asset' + (show_empty ? '' : ' WHERE value > 0') + ' ORDER BY value DESC').map do |r|
      {
        address: r['address'],
        login: r['login'],
        value: r['value'].to_i,
        updated: Time.parse(r['updated']),
        hot: !r['pvt'].nil?
      }
    end
  end

  # Return all addresses with private keys open.
  def disclose
    @pgsql.exec('SELECT * FROM asset WHERE pvt IS NOT NULL').map do |r|
      {
        address: r['address'],
        login: r['login'],
        pvt: @codec.decrypt(r['pvt']),
        value: r['value'].to_i
      }
    end
  end

  # Get owner of the address.
  def owner(address)
    row = @pgsql.exec('SELECT login FROM asset WHERE address = $1', [address])[0]
    raise WTS::UserError, "E197: The owner of #{address} not found" if row.nil?
    row['login']
  end

  # This address has an owner?
  def owned?(address)
    !@pgsql.exec('SELECT * FROM asset WHERE address = $1 AND login IS NOT NULL', [address]).empty?
  end

  # This address is cold?
  def cold?(address)
    !@pgsql.exec('SELECT * FROM asset WHERE address = $1 AND pvt IS NULL', [address]).empty?
  end

  # Current price of BTC in USD.
  def price
    @sibit.price
  end

  # Recheck the blockchain and update balances.
  def reconcile
    done = 0
    errors = 0
    all(show_empty: true).each do |a|
      after = @sibit.balance(a[:address])
      unless after == a[:value]
        set(a[:address], after)
        yield(a[:address], a[:value], after, a[:hot])
      end
      done += 1
    rescue Sibit::Error => e
      @log.info("Failed to reconcile #{a[:address]} Bitcoin address: #{e.message}")
      errors += 1
    end
    @log.info("Reconciled #{done} Bitcoin addresses (#{errors} errors)")
  end

  # Get total BTC balance, in BTC (as float).
  def balance(hot_only: false)
    @pgsql.exec(
      'SELECT SUM(value) FROM asset' + (hot_only ? ' WHERE pvt IS NOT NULL' : '')
    )[0]['sum'].to_f / 100_000_000
  end

  # Create a new asset/address for a given user (return existing one if it is
  # already in the database). When a new address is assigned, a block given
  # will be called. If the login is NIL, a "change" address will be returned.
  def acquire(login = nil)
    row = if login.nil?
      @pgsql.exec(
        [
          'SELECT address FROM asset',
          'WHERE login IS NULL AND pvt IS NOT NULL',
          'ORDER BY RANDOM()',
          'LIMIT 1 OFFSET 7'
        ].join(' ')
      )[0]
    else
      @pgsql.exec('SELECT address FROM asset WHERE login = $1', [login])[0]
    end
    if row.nil?
      sibit = Sibit.new(log: @log)
      pvt = sibit.generate
      address = sibit.create(pvt)
      encrypted = @codec.encrypt(pvt)
      @pgsql.exec(
        'INSERT INTO asset (address, login, pvt) VALUES ($1, $2, $3)',
        [address, login, encrypted]
      )
      yield(login, address, encrypted) if block_given?
      @log.info("Bitcoin address #{address} acquired by #{login.inspect}")
      address
    else
      row['address']
    end
  end

  # Add cold asset.
  def add_cold(address)
    @pgsql.exec('INSERT INTO asset (address) VALUES ($1)', [address])
    set(address, @sibit.balance(address))
  end

  # Set the balance of an assert.
  def set(address, value)
    before = @pgsql.exec('SELECT value FROM asset WHERE address = $1', [address])[0]
    raise "Asset #{address} is absent" if before.nil?
    before = before['value'].to_i
    @pgsql.exec('UPDATE asset SET value = $1, updated = NOW() WHERE address = $2', [value, address])
    @log.info("Bitcoin balance of #{address} reset from #{before} to #{value}")
  end

  # Get the latest block from the blockchain, scan all transactions visible
  # there and find those, which we are waiting for. Then, yield them one
  # by one if they haven't been seen yet in UTXOs.
  def monitor(seen, max: 1)
    raise "Wrong BTC address '#{seen}'" unless seen.length == 64
    nxt = @sibit.next_of(seen)
    return seen if nxt.nil?
    return seen unless nxt.start_with?('00000000')
    ours = Set.new(@pgsql.exec('SELECT address FROM asset').map { |r| r['address'] })
    @sibit.scan(nxt, max: max) do |receiver, hash, satoshi|
      next unless ours.include?(receiver)
      if seen?(hash)
        @log.info("Hash #{hash} has already been seen, ignoring now...")
        next
      end
      set(receiver, @sibit.balance(receiver))
      yield(receiver, hash, satoshi)
      true
    end
  end

  # Send a payment to the address.
  def pay(address, satoshi)
    batch = {}
    unspent = 0
    @pgsql.exec('SELECT * FROM asset WHERE value > 0 ORDER BY value').each do |r|
      next if r['pvt'].nil?
      batch[r['address']] = @codec.decrypt(r['pvt'])
      unspent += r['value'].to_i
      break if unspent > satoshi
    end
    if unspent < satoshi
      raise "Not enough funds to send #{satoshi}, only #{unspent} left in #{batch.count} Bitcoin addresses"
    end
    txn = @sibit.pay(satoshi, '-L', batch, address, acquire)
    batch.each_key { |a| set(a, 0) }
    @log.info("Sent #{satoshi} to #{address} from #{batch.count} addresses: #{batch.keys.join(', ')}; \
total unspent was #{unspent}; tx hash is #{txn}")
    txn
  end

  def seen?(hash)
    !@pgsql.exec('SELECT * FROM utxo WHERE hash = $1', [hash]).empty?
  end

  # This UTXO has been seen, for the provided Bitcoin address.
  def see(address, hash)
    @pgsql.exec(
      'INSERT INTO utxo (address, hash) VALUES ($1, $2) ON CONFLICT(address, hash) DO NOTHING',
      [address, hash]
    )
    @log.info("Bitcoin tx hash #{hash} recorded as seen at #{address}")
  end
end
