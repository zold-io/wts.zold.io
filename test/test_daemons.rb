# SPDX-FileCopyrightText: Copyright (c) 2018-2025 Zerocracy
# SPDX-License-Identifier: MIT

require 'minitest/autorun'
require 'webmock/minitest'
require_relative 'test__helper'
require_relative '../objects/daemons'

class WTS::DaemonsTest < Minitest::Test
  def test_start_and_stop
    WebMock.allow_net_connect!
    daemons = WTS::Daemons.new(t_pgsql, log: t_log)
    started = false
    daemons.start('test', 0, pause: 0) do
      started = true
    end
    sleep 0.1
    assert(started)
  end

  def test_start_and_run_a_broken_thread
    WebMock.allow_net_connect!
    daemons = WTS::Daemons.new(t_pgsql, log: t_log)
    stepped = 0
    daemons.start('test-errors', 0, pause: 0) do
      stepped += 1
      raise StandardError, 'Intended' if stepped == 1
    end
    sleep 0.1
    assert(stepped > 1)
  end
end
