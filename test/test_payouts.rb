# SPDX-FileCopyrightText: Copyright (c) 2018-2025 Zerocracy
# SPDX-License-Identifier: MIT

require 'minitest/autorun'
require 'webmock/minitest'
require 'zold/amount'
require_relative 'test__helper'
require_relative '../objects/payouts'

class WTS::PayoutsTest < Minitest::Test
  def test_register_and_check
    WebMock.allow_net_connect!
    payouts = WTS::Payouts.new(t_pgsql, log: t_log)
    login = 'yegor256'
    payouts.add(login, Zold::Id::ROOT.to_s, Zold::Amount.new(zld: 16.0), 'just for fun')
    assert_equal(1, payouts.fetch(login).count)
    assert(payouts.fetch_all.count >= 1)
    assert(payouts.allowed?(login, Zold::Amount.new(zld: 3.0)))
  end
end
