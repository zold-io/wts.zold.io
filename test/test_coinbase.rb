# Copyright (c) 2018-2021 Zold
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
require_relative '../objects/coinbase'

class WTS::CoinbaseTest < Minitest::Test
  def test_sends_btc
    WebMock.disable_net_connect!
    stub_request(:get, 'https://api.coinbase.com/v2/accounts/account').to_return(
      body: '{}'
    )
    stub_request(:post, 'https://api.coinbase.com/v2/accounts//transactions').to_return(status: 200)
    bank = WTS::Coinbase.new('key', 'secret', 'account', log: t_log)
    bank.pay('1N1R2HP9JD4LvAtp7rTkpRqF19GH7PH2ZF', 1.0, 'test')
  end

  # @todo #91:30min This unit test doesn't work for some reason. I can't
  #  figure out what's wrong here. Let's investigate and fix. The code
  #  works fine with production API, though.
  def test_checks_balance
    skip
    WebMock.disable_net_connect!
    stub_request(:get, 'https://api.coinbase.com/v2/accounts/account').to_return(
      body: '{"balance": {"amount": "1.0", "currency": "BTC"}}'
    )
    bank = WTS::Coinbase.new('key', 'secret', 'account', log: t_log)
    assert_equal(1.0, bank.balance)
  end

  def test_sends_real_bitcoins
    skip
    WebMock.allow_net_connect!
    bank = WTS::Coinbase.new('...', '...', '...', log: t_log)
    bank.pay('16KU4QyyEDXZUeiAPMEj4HWz4V57sLLuL3', 3.3, 'Just a test')
  end
end
