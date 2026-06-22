# frozen_string_literal: true

# SPDX-FileCopyrightText: Copyright (c) 2018-2026 Zerocracy
# SPDX-License-Identifier: MIT

require_relative '../objects/graph'
require_relative '../objects/ticks'
require_relative '../objects/user_error'
require_relative 'test__helper'

class WTS::GraphTest < Minitest::Test
  def test_renders_svg
    WebMock.allow_net_connect!
    ticks = WTS::Ticks.new(t_pgsql, log: t_log)
    ticks.add('Price' => 1, 'time' => msec(-1))
    ticks.add('Price' => 3, 'time' => msec(-2))
    ticks.add('Price' => 2, 'time' => msec(-10))
    ticks.add('Price' => 1.5, 'time' => msec(-14))
    ticks.add('Price' => 1.2, 'time' => msec(-50))
    FileUtils.mkdir_p('target')
    File.write('target/graph.svg', WTS::Graph.new(ticks, log: t_log).svg(['Price'], 1, 0))
  end

  def test_rejects_negative_digits
    assert_raises(WTS::UserError) do
      WTS::Graph.new(nil, log: t_log).svg(['Price'], 1, -1)
    end
  end

  private

  def msec(days)
    ((Time.now.to_f + (days * 24 * 60 * 60)) * 1000).to_i
  end
end
