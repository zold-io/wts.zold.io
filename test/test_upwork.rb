# frozen_string_literal: true

# SPDX-FileCopyrightText: Copyright (c) 2018-2026 Zerocracy
# SPDX-License-Identifier: MIT

require_relative '../objects/upwork'
require_relative '../objects/wts'
require_relative 'test__helper'

class WTS::UpworkTest < Minitest::Test
  def test_sends_upwork
    skip
    WebMock.allow_net_connect!
    refute_nil(
      WTS::Upwork.new(
        {
          'consumer_key' => '...',
          'consumer_secret' => '...',
          'access_token' => '...',
          'access_secret' => '...'
        },
        'team_id',
        log: t_log
      ).pay('123456789', 1.28, 'Just a test')
    )
  end
end
