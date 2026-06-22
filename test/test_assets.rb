# frozen_string_literal: true

# SPDX-FileCopyrightText: Copyright (c) 2018-2026 Zerocracy
# SPDX-License-Identifier: MIT

require 'glogin'
require 'zold'
require_relative '../objects/assets'
require_relative '../objects/item'
require_relative '../objects/wts'
require_relative 'test__helper'

class FakeMonitor
  def acquired(addr)
    @addr = addr
  end

  def latest
    'x1'
  end

  def balance(_)
    500
  end

  def next_of(_)
    '0000000000000000000c41262afa6c0e82c47c89dd5fe8c692f33788077ec5b8'
  end

  def block(_)
    {
      hash: 'x',
      orphan: false,
      next: 'x',
      previous: 'x',
      txns: [
        {
          hash: 'x',
          outputs: [
            {
              address: @addr,
              value: 1000
            }
          ]
        }
      ]
    }
  end
end

class WTS::AssetsTest < Minitest::Test
  def test_acquire_address
    WebMock.allow_net_connect!
    login = "jeff#{rand(999)}"
    WTS::Item.new(login, t_pgsql, log: t_log).create(Zold::Id.new, Zold::Key.new(text: OpenSSL::PKey::RSA.new(2048).to_pem))
    assets = WTS::Assets.new(t_pgsql, log: t_log)
    address = assets.acquire(login)
    refute_nil(address)
    assert_equal(address, assets.acquire(login))
    assert_equal(login, assets.owner(address))
    refute_empty(assets.disclose)
  end

  def test_orphan_address
    WebMock.allow_net_connect!
    assets = WTS::Assets.new(t_pgsql, log: t_log)
    addresses = Set.new
    200.times { addresses << assets.acquire }
    assert_equal(8, addresses.count)
  end

  def test_add_cold_asset
    WebMock.allow_net_connect!
    assets = WTS::Assets.new(t_pgsql, log: t_log, sibit: Sibit::Fake.new)
    address = "1JvCsJtLmCxEk7ddZFnVkGXpr9uhxZP#{rand(999)}"
    assets.add_cold(address)
    assert(assets.cold?(address))
  end

  def test_sets_value
    WebMock.allow_net_connect!
    assets = WTS::Assets.new(t_pgsql, log: t_log)
    address = assets.acquire
    assets.set(address, 50_000_000)
    assets.set(address, 100_000_000)
    refute(assets.cold?(address))
    assert_equal(100_000_000, assets.all.find { |a| a[:address] == address }[:value])
    assert_operator(assets.balance, :>=, 1, assets.balance)
  end

  def test_monitors_blockchain
    login = "jeff#{rand(999)}"
    WTS::Item.new(login, t_pgsql, log: t_log).create(Zold::Id.new, Zold::Key.new(text: OpenSSL::PKey::RSA.new(2048).to_pem))
    api = FakeMonitor.new
    assets = WTS::Assets.new(t_pgsql, log: t_log, sibit: Sibit.new(api: api))
    api.acquired(assets.acquire(login))
    found = false
    before = '0000000000000000000c41262afa6c0e82c47c89dd5fe8c692f33788077ec5b8'
    assets.monitor(before, max: 2) do |a, hsh, satoshi|
      refute_nil(a)
      refute_nil(hsh)
      refute_nil(satoshi)
      found = true
    end
    assert(found)
  end

  def test_pays
    WebMock.allow_net_connect!
    assets = WTS::Assets.new(
      t_pgsql,
      log: t_log,
      sibit: Sibit.new(api: Sibit::Fake.new),
      codec: GLogin::Codec.new('some secret')
    )
    ["jeff#{rand(999)}", "johnny#{rand(999)}"].each do |login|
      WTS::Item.new(login, t_pgsql, log: t_log).create(Zold::Id.new, Zold::Key.new(text: OpenSSL::PKey::RSA.new(2048).to_pem))
      assets.set(assets.acquire(login), 70)
    end
    assert_raises(Sibit::Error) do
      assets.pay("1JvCsJtLmCxEk7ddZFnVkGXpr9uhxZP#{rand(999)}", 100)
    end
  end

  def test_saves_hash_and_loads
    WebMock.allow_net_connect!
    assets = WTS::Assets.new(t_pgsql, log: t_log)
    address = "1JvCsJtLmCxEk7ddZFnVkGXpr9uhxZP#{rand(999)}"
    hash = "5de641d3867eb8fec3eb1a5ef2b44df39b54e0b3bb664ab520f2ae26a5b18#{rand(999)}"
    refute(assets.seen?(hash))
    assets.see(address, hash)
    assets.see(address, hash)
    assert(assets.seen?(hash))
    other = "5de641d3867eb8fec3eb1a5ef2b44df39b54e0b3bb664ab520f2ae26a5b19#{rand(999)}"
    assets.see(address, other)
    assert(assets.seen?(other))
  end
end
