# frozen_string_literal: true

# SPDX-FileCopyrightText: Copyright (c) 2018-2026 Zerocracy
# SPDX-License-Identifier: MIT

require_relative '../objects/ticks'
require_relative 'test__helper'

class WTS::TicksTest < Minitest::Test
  def test_create_and_read
    WebMock.allow_net_connect!
    ticks = WTS::Ticks.new(t_pgsql, log: t_log)
    ticks.add('foo' => 124)
    assert_operator(ticks.fetch('foo').count, :>=, 1)
    assert(ticks.exists?('foo'))
  end
end
