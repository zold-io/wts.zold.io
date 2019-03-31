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
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

require 'minitest/autorun'
require 'webmock/minitest'
require_relative 'test__helper'
require_relative '../objects/wts'
require_relative '../objects/btc'
require_relative '../objects/addresses'

class WTS::BtcTest < Minitest::Test
  # Fake BTC
  class FakeBtc
    def initialize(addr)
      @addr = addr
    end

    def create
      { hash: @addr, pvt: 'empty' }
    end
  end

  def test_creates_address
    WebMock.disable_net_connect!
    btc = WTS::Btc.new(log: test_log)
    address = btc.create
    assert(!address[:hash].nil?)
    assert(!address[:pvt].nil?)
  end

  def test_validates_txn
    btc = WTS::Btc.new(log: test_log)
    assert(btc.trustable?(27_900, 6))
  end

  def test_monitors_txns
    WebMock.allow_net_connect!
    btc = WTS::Btc.new(log: test_log)
    addresses = WTS::Addresses.new(WTS::Pgsql::TEST.start, log: test_log)
    addr = '1BPs843gTEkfNk9LL6Lr2QyRNmWtQvJejv'
    addresses.acquire('johnny-l09', FakeBtc.new(addr))
    btc.monitor(addresses) do |hash, txn, satoshi, confirmations|
      assert_equal(addr, hash)
      assert_equal('154a7dfd574abbc5d22ebca1b8ca9358dcf545e84eaffb46c4978b981af9c13e', txn)
      assert_equal(25_800, satoshi)
      assert(confirmations > 100)
    end
  end
end
