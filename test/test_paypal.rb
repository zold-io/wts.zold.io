# SPDX-FileCopyrightText: Copyright (c) 2018-2025 Zerocracy
# SPDX-License-Identifier: MIT

require 'minitest/autorun'
require 'webmock/minitest'
require_relative 'test__helper'
require_relative '../objects/wts'
require_relative '../objects/paypal'

class WTS::PayPalTest < Minitest::Test
  def test_sends_paypal
    skip
    WebMock.allow_net_connect!
    pp = WTS::PayPal.new(
      {
        id: 'Aayp...',
        secret: 'EDP...',
        email: 'pp@zerocracy.com',
        login: '...',
        password: '...',
        signature: '...',
        appid: 'APP-...'
      },
      log: t_log
    )
    key = pp.pay('yegor256@gmail.com', 1.28, 'Just a test')
    assert(key.start_with?('AP-'), key)
  end
end
