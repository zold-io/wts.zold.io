# SPDX-FileCopyrightText: Copyright (c) 2018-2025 Zerocracy
# SPDX-License-Identifier: MIT

require 'minitest/autorun'
require 'webmock/minitest'
require_relative 'test__helper'
require_relative '../objects/ticks'

class WTS::TicksTest < Minitest::Test
  def test_create_and_read
    WebMock.allow_net_connect!
    ticks = WTS::Ticks.new(t_pgsql, log: t_log)
    ticks.add('foo' => 124)
    assert(ticks.fetch('foo').count >= 1)
    assert(ticks.exists?('foo'))
  end
end
