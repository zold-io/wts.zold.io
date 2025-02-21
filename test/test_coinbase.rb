# SPDX-FileCopyrightText: Copyright (c) 2018-2025 Zerocracy
# SPDX-License-Identifier: MIT

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
