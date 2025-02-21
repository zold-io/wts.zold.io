# SPDX-FileCopyrightText: Copyright (c) 2018-2025 Zerocracy
# SPDX-License-Identifier: MIT

require 'minitest/autorun'
require 'webmock/minitest'
require_relative 'test__helper'
require_relative '../objects/mcodes'

class WTS::McodesTest < Minitest::Test
  def test_saves_and_gets
    WebMock.allow_net_connect!
    mcodes = WTS::Mcodes.new(t_pgsql, log: t_log)
    phone = 1_234_567_890
    assert(!mcodes.exists?(phone))
    mcodes.set(phone, 1234)
    assert(mcodes.exists?(phone))
    assert_equal(1234, mcodes.get(phone))
    mcodes.remove(phone)
    assert_raises WTS::UserError do
      mcodes.get(phone)
    end
  end
end
