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
require 'openssl'
require 'zold/key'
require 'zold/id'
require 'zold/http'
require_relative 'test__helper'
require_relative '../objects/dynamo'
require_relative '../objects/item'

class ItemTest < Minitest::Test
  def test_create_and_read
    WebMock.allow_net_connect!
    item = Item.new('jeff', Dynamo.new.aws)
    assert(!item.exists?)
    pvt = OpenSSL::PKey::RSA.new(2048)
    id = Zold::Id.new
    item.create(id, Zold::Key.new(text: pvt.to_pem))
    assert(item.exists?)
  end

  def test_wipes_keygap
    WebMock.allow_net_connect!
    item = Item.new('jeffrey1', Dynamo.new.aws)
    pvt = OpenSSL::PKey::RSA.new(2048)
    id = Zold::Id.new
    pem = pvt.to_pem
    key = Zold::Key.new(text: pem)
    keygap = item.create(id, key)
    assert_equal(key, item.key(keygap))
    assert_equal(id, item.id)
    assert(!item.wiped?)
    item.wipe(keygap)
    assert(item.wiped?)
    assert_equal(key, item.key(keygap))
  end

  def test_reads_btc_address
    WebMock.allow_net_connect!
    jeff = Item.new('jeffrey2', Dynamo.new.aws)
    sarah = Item.new('sarah2', Dynamo.new.aws)
    pvt = OpenSSL::PKey::RSA.new(2048)
    jeff.create(Zold::Id.new, Zold::Key.new(text: pvt.to_pem))
    sarah.create(Zold::Id.new, Zold::Key.new(text: pvt.to_pem))
    btc1 = '32wtFfKbjWHpu9WFzX9adGssnAosqPkSp6'
    assert(jeff.btc { btc1 })
    assert_equal(btc1, jeff.btc)
    btc2 = '32wtFfKbjWHpu9WFzX9adGssnAosqPkSp7'
    assert(sarah.btc { btc2 })
    assert_equal(btc2, sarah.btc)
    sleep 0.5
    assert(jeff.btc(lifetime: 0.2) { raise 'Should not happen' })
    assert(btc1 != jeff.btc)
  end

  def test_sets_and_resets_api_token
    WebMock.allow_net_connect!
    item = Item.new('johnny2', Dynamo.new.aws)
    pvt = OpenSSL::PKey::RSA.new(2048)
    item.create(Zold::Id.new, Zold::Key.new(text: pvt.to_pem))
    token = item.token
    assert_equal(token, item.token)
    item.token_reset
    assert(token != item.token)
  end

  def test_sets_and_resets_mcode
    WebMock.allow_net_connect!
    item = Item.new('johnny99', Dynamo.new.aws)
    pvt = OpenSSL::PKey::RSA.new(2048)
    item.create(Zold::Id.new, Zold::Key.new(text: pvt.to_pem))
    item.mcode_set(1234)
    assert_equal(1234, item.mcode)
    item.mcode_set(5566)
    assert_equal(5566, item.mcode)
  end
end
