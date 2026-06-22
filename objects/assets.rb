# frozen_string_literal: true

# SPDX-FileCopyrightText: Copyright (c) 2018-2026 Zerocracy
# SPDX-License-Identifier: MIT

require 'glogin'
require 'loog'
require 'retriable'
require 'sibit'
require_relative 'user_error'
require_relative 'wts'

class WTS::Assets
  def initialize(pgsql, log: Loog::NULL, sibit: Sibit.new(log: @log), codec: GLogin::Codec.new)
    @pgsql = pgsql
    @log = log
    @sibit = sibit
    @codec = codec
  end

  def all(show_empty: false)
    @pgsql.exec("SELECT * FROM asset#{' WHERE value > 0' unless show_empty} ORDER BY value DESC").map do |r|
      {
        address: r['address'],
        login: r['login'],
        value: r['value'].to_i,
        updated: Time.parse(r['updated']),
        hot: !r['pvt'].nil?
      }
    end
  end

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

  def owner(address)
    row = @pgsql.exec('SELECT login FROM asset WHERE address = $1', [address])[0]
    raise(WTS::UserError, "E197: The owner of #{address} not found") if row.nil?
    row['login']
  end

  def owned?(address)
    !@pgsql.exec('SELECT * FROM asset WHERE address = $1 AND login IS NOT NULL', [address]).empty?
  end

  def cold?(address)
    !@pgsql.exec('SELECT * FROM asset WHERE address = $1 AND pvt IS NULL', [address]).empty?
  end

  def price
    @sibit.price
  end

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

  def balance(hot_only: false)
    @pgsql.exec(
      "SELECT SUM(value) FROM asset#{' WHERE pvt IS NOT NULL' if hot_only}"
    )[0]['sum'].to_f / 100_000_000
  end

  def acquire(login = nil)
    row =
      if login.nil?
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
      @pgsql.exec('INSERT INTO asset (address, login, pvt) VALUES ($1, $2, $3)', [address, login, encrypted])
      yield(login, address, encrypted) if block_given?
      @log.info("Bitcoin address #{address} acquired by #{login.inspect}")
      address
    else
      row['address']
    end
  end

  def add_cold(address)
    @pgsql.exec('INSERT INTO asset (address) VALUES ($1)', [address])
    set(address, @sibit.balance(address))
  end

  def set(address, value)
    before = @pgsql.exec('SELECT value FROM asset WHERE address = $1', [address])[0]
    raise(RuntimeError, "Asset #{address} is absent") if before.nil?
    before = before['value'].to_i
    @pgsql.exec('UPDATE asset SET value = $1, updated = NOW() WHERE address = $2', [value, address])
    @log.info("Bitcoin balance of #{address} reset from #{before} to #{value}")
  end

  def monitor(seen, max: 1)
    raise(RuntimeError, "Wrong BTC address '#{seen}'") unless seen.length == 64
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
      raise(
        RuntimeError,
        "Not enough funds to send #{satoshi}, only #{unspent} left in #{batch.count} Bitcoin addresses"
      )
    end
    txn = @sibit.pay(satoshi, '-L', batch.values, address, acquire)
    batch.each_key { |a| set(a, 0) }
    @log.info(
      "Sent #{satoshi} to #{address} from #{batch.count} addresses: #{batch.keys.join(', ')}; " \
      "total unspent was #{unspent}; tx hash is #{txn}"
    )
    txn
  end

  def seen?(hash)
    !@pgsql.exec('SELECT * FROM utxo WHERE hash = $1', [hash]).empty?
  end

  def see(address, hash)
    @pgsql.exec(
      'INSERT INTO utxo (address, hash) VALUES ($1, $2) ON CONFLICT(address, hash) DO NOTHING',
      [address, hash]
    )
    @log.info("Bitcoin tx hash #{hash} recorded as seen at #{address}")
  end
end
