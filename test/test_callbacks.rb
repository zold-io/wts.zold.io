# Copyright (c) 2018-2023 Zold
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the 'Software'), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED 'AS IS', WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

require 'minitest/autorun'
require 'webmock/minitest'
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
    assert(callbacks.fetch(login)[0][:matched].nil?)
    tid = "#{id}:1"
    assert(!callbacks.match(tid, id.to_s, 'NOPREFIX', 'for pizza').empty?)
    assert(!callbacks.fetch(login)[0][:matched].nil?)
    assert(callbacks.match(tid, id.to_s, 'NOPREFIX', 'for pizza').empty?)
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
    callbacks.repeat_succeeded
    callbacks.delete_failed
    callbacks.delete_expired
    assert_requested(get, times: 1)
  end
end
