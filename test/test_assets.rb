# Copyright (c) 2018-2020 Zerocracy, Inc.
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
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

require 'minitest/autorun'
require 'webmock/minitest'
require 'zold'
require 'glogin'
require_relative 'test__helper'
require_relative '../objects/wts'
require_relative '../objects/assets'
require_relative '../objects/item'

class WTS::AssetsTest < Minitest::Test
  def test_acquire_address
    WebMock.allow_net_connect!
    login = "jeff#{rand(999)}"
    item = WTS::Item.new(login, t_pgsql, log: t_log)
    item.create(Zold::Id.new, Zold::Key.new(text: OpenSSL::PKey::RSA.new(2048).to_pem))
    assets = WTS::Assets.new(t_pgsql, log: t_log)
    address = assets.acquire(login)
    assert(!address.nil?)
    assert_equal(address, assets.acquire(login))
    assert_equal(login, assets.owner(address))
    assert(!assets.disclose.empty?)
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
    assert(!assets.cold?(address))
    assert_equal(100_000_000, assets.all.select { |a| a[:address] == address }[0][:value])
    assert(assets.balance >= 1, assets.balance)
  end

  def test_monitors_blockchain
    login = "jeff#{rand(999)}"
    item = WTS::Item.new(login, t_pgsql, log: t_log)
    item.create(Zold::Id.new, Zold::Key.new(text: OpenSSL::PKey::RSA.new(2048).to_pem))
    api = Object.new
    def api.acquired(a)
      @addr = a
    end
    assets = WTS::Assets.new(t_pgsql, log: t_log, sibit: Sibit.new(api: api))
    addr = assets.acquire(login)
    api.acquired(addr)
    def api.latest
      'x1'
    end

    def api.balance(_)
      500
    end

    def api.block(_)
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
    found = false
    assets.monitor('before', max: 2) do |a, hsh, satoshi|
      assert(!a.nil?)
      assert(!hsh.nil?)
      assert(!satoshi.nil?)
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
      item = WTS::Item.new(login, t_pgsql, log: t_log)
      item.create(Zold::Id.new, Zold::Key.new(text: OpenSSL::PKey::RSA.new(2048).to_pem))
      assets.set(assets.acquire(login), 70)
    end
    ex = assert_raises(Sibit::Error) do
      assets.pay("1JvCsJtLmCxEk7ddZFnVkGXpr9uhxZP#{rand(999)}", 100)
    end
    assert(ex.message.include?('Not enough funds'))
  end

  def test_saves_hash_and_loads
    WebMock.allow_net_connect!
    assets = WTS::Assets.new(t_pgsql, log: t_log)
    address = "1JvCsJtLmCxEk7ddZFnVkGXpr9uhxZP#{rand(999)}"
    hash = "5de641d3867eb8fec3eb1a5ef2b44df39b54e0b3bb664ab520f2ae26a5b18#{rand(999)}"
    assert(!assets.seen?(hash))
    assets.see(address, hash)
    assets.see(address, hash)
    assert(assets.seen?(hash))
    hash2 = "5de641d3867eb8fec3eb1a5ef2b44df39b54e0b3bb664ab520f2ae26a5b19#{rand(999)}"
    assets.see(address, hash2)
    assert(assets.seen?(hash2))
  end
end
