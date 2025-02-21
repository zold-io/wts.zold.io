# SPDX-FileCopyrightText: Copyright (c) 2018-2025 Zerocracy
# SPDX-License-Identifier: MIT

require 'minitest/autorun'
require 'webmock/minitest'
require_relative 'test__helper'
require_relative '../objects/wts'
require_relative '../objects/upwork'

class WTS::UpworkTest < Minitest::Test
  def test_sends_upwork
    skip
    WebMock.allow_net_connect!
    upwork = WTS::Upwork.new(
      {
        'consumer_key' => '...',
        'consumer_secret' => '...',
        'access_token' => '...',
        'access_secret' => '...'
      },
      'team_id',
      log: t_log
    )
    key = upwork.pay('123456789', 1.28, 'Just a test')
    assert(!key.nil?)
  end
end
