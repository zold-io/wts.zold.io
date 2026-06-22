# frozen_string_literal: true

# SPDX-FileCopyrightText: Copyright (c) 2018-2026 Zerocracy
# SPDX-License-Identifier: MIT

require 'telepost'
require 'zold/amount'
require_relative '../objects/callbacks'
require_relative 'test__helper'

class WTS::CallbacksTest < Minitest::Test
  def test_register_and_ping
    WebMock.allow_net_connect!
    callbacks = WTS::Callbacks.new(t_pgsql, log: t_log)
    id = Zold::Id.new
    login = 'yegor256'
    callbacks.restart(callbacks.add(login, id.to_s, 'NOPREFIX', /pizza/, 'http://localhost:888/'))
    assert_equal(1, callbacks.fetch(login).count)
    assert_nil(callbacks.fetch(login)[0][:matched])
    tid = "#{id}:1"
    refute_empty(callbacks.match(tid, id.to_s, 'NOPREFIX', 'for pizza'))
    refute_nil(callbacks.fetch(login)[0][:matched])
    assert_empty(callbacks.match(tid, id.to_s, 'NOPREFIX', 'for pizza'))
    callbacks.ping do
      [
        Zold::Txn.new(1, Time.now, Zold::Amount.new(zld: 1.99), 'NOPREFIX', Zold::Id.new, '-')
      ]
    end
    callbacks.delete_succeeded
    callbacks.repeat_succeeded
    callbacks.delete_failed
    callbacks.delete_expired
    assert_requested(stub_request(:get, /localhost:888/).to_return(body: 'OK'), times: 1)
  end
end
