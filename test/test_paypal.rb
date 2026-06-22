# frozen_string_literal: true

# SPDX-FileCopyrightText: Copyright (c) 2018-2026 Zerocracy
# SPDX-License-Identifier: MIT

require_relative '../objects/paypal'
require_relative '../objects/wts'
require_relative 'test__helper'

class WTS::PayPalTest < Minitest::Test
  def test_sends_paypal
    skip
    WebMock.allow_net_connect!
    assert(
      WTS::PayPal.new(
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
      ).pay('yegor256@gmail.com', 1.28, 'Just a test').start_with?('AP-')
    )
  end
end
