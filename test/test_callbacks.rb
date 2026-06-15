# SPDX-FileCopyrightText: Copyright (c) 2018-2026 Zerocracy
# SPDX-License-Identifier: MIT

require 'securerandom'
require 'zold/amount'
require 'telepost'
require_relative 'test__helper'
require_relative '../objects/callbacks'

class WTS::CallbacksTest < Minitest::Test
  def test_register_and_ping
    WebMock.allow_net_connect!
    callbacks = WTS::Callbacks.new(t_pgsql, log: t_log)
    id = Zold::Id.new
    login = 'yegor256'
    cid = callbacks.add(login, id.to_s, 'NOPREFIX', /pizza/, 'http://localhost:888/')
    callbacks.restart(cid)
    assert_equal(1, callbacks.fetch(login).count)
    assert_nil(callbacks.fetch(login)[0][:matched])
    tid = "#{id}:1"
    refute_empty(callbacks.match(tid, id.to_s, 'NOPREFIX', 'for pizza'))
    refute_nil(callbacks.fetch(login)[0][:matched])
    assert_empty(callbacks.match(tid, id.to_s, 'NOPREFIX', 'for pizza'))
    get = stub_request(:get, /localhost:888/).to_return(body: 'OK')
    callbacks.ping do
      [
        Zold::Txn.new(
          1, Time.now,
          Zold::Amount.new(zld: 1.99),
          'NOPREFIX',
          Zold::Id.new, '-'
        )
      ]
    end
    callbacks.delete_succeeded
    repeated = []
    callbacks.repeat_succeeded { |c| repeated << c }
    callbacks.delete_failed
    callbacks.delete_expired
    assert_requested(get, times: 1)
    assert_empty(repeated)
  end

  def test_repeat_succeeded_yields_callback
    WebMock.allow_net_connect!
    callbacks = WTS::Callbacks.new(t_pgsql, log: t_log)
    id = Zold::Id.new
    login = "repeat_#{SecureRandom.hex(4)}"
    cid = callbacks.add(login, id.to_s, 'NOPREFIX', /pizza/, 'http://localhost:889/', repeat: true)
    callbacks.restart(cid)
    tid = "#{id}:1"
    refute_empty(callbacks.match(tid, id.to_s, 'NOPREFIX', 'for pizza'))
    stub_request(:get, /localhost:889/).to_return(body: 'OK')
    callbacks.ping do
      [
        Zold::Txn.new(
          1, Time.now,
          Zold::Amount.new(zld: 1.99),
          'NOPREFIX',
          Zold::Id.new, '-'
        )
      ]
    end
    yielded = []
    callbacks.repeat_succeeded { |c| yielded << c }
    assert_equal(1, yielded.count)
    assert_equal(cid, yielded.first[:id])
    assert_equal(login, yielded.first[:login])
  end
end
