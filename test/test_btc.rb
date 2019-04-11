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
require_relative '../objects/assets'
require_relative '../objects/utxos'
require_relative '../objects/item'

class WTS::BtcTest < Minitest::Test
  def test_monitors_blockchain
    WebMock.allow_net_connect!
    btc = WTS::Btc.new(log: test_log)
    assets = WTS::Assets.new(WTS::Pgsql::TEST.start, log: test_log)
    utxos = WTS::Utxos.new(WTS::Pgsql::TEST.start, log: test_log)
    login = "jeff#{rand(999)}"
    item = WTS::Item.new(login, WTS::Pgsql::TEST.start, log: test_log)
    item.create(Zold::Id.new, Zold::Key.new(text: OpenSSL::PKey::RSA.new(2048).to_pem))
    assets.acquire(login)
    btc.monitor(assets, utxos, '', max: 2) do |address, hash, satoshi|
      assert(!address.nil?)
    end
  end
end
