# Copyright (c) 2018-2025 Zerocracy
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
