# frozen_string_literal: true

# SPDX-FileCopyrightText: Copyright (c) 2018-2026 Zerocracy
# SPDX-License-Identifier: MIT

require 'zold/amount'
require_relative '../objects/payouts'
require_relative 'test__helper'

class WTS::PayoutsTest < Minitest::Test
  def test_register_and_check
    WebMock.allow_net_connect!
    payouts = WTS::Payouts.new(t_pgsql, log: t_log)
    login = 'yegor256'
    payouts.add(login, Zold::Id::ROOT.to_s, Zold::Amount.new(zld: 16.0), 'just for fun')
    assert_equal(1, payouts.fetch(login).count)
    assert_operator(payouts.all.count, :>=, 1)
    assert(payouts.allowed?(login, Zold::Amount.new(zld: 3.0)))
  end
end
