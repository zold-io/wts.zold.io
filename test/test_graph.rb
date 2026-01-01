# SPDX-FileCopyrightText: Copyright (c) 2018-2026 Zerocracy
# SPDX-License-Identifier: MIT

require_relative 'test__helper'
require_relative '../objects/ticks'
require_relative '../objects/graph'

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

  private

  def msec(days)
    ((Time.now.to_f + (days * 24 * 60 * 60)) * 1000).to_i
  end
end
