# Copyright (c) 2018-2019 Zerocracy, Inc.
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
require_relative 'test__helper'
require_relative '../objects/pgsql'
require_relative '../objects/addresses'

class AddressesTest < Minitest::Test
  def test_reads_btc_address
    WebMock.allow_net_connect!
    addresses = Addresses.new(Pgsql::TEST.start, log: test_log)
    btc1 = "32wtFfKbjWHpu9WFzX9adGsstAosqPk#{rand(999)}"
    assert_equal(btc1, addresses.acquire("jeff-#{rand(999)}") { btc1 })
    btc2 = "32wtFfKbjWHpu9WFzX9adGsFFAosqPk#{rand(999)}"
    john = "john-#{rand(999)}"
    assert_equal(btc2, addresses.acquire(john) { btc2 })
    assert_equal(john, addresses.find_user(btc2))
    assert(addresses.all.count >= 2)
    assert(!addresses.arrived?(john))
    addresses.arrived(btc2, john)
    assert(addresses.arrived?(john))
    assert(!addresses.mtime(john).nil?)
    addresses.destroy(btc2, john)
  end

  def test_swaps
    WebMock.allow_net_connect!
    addresses = Addresses.new(Pgsql::TEST.start, log: test_log)
    btc = "32wtFfKbjWHpu9WFzX9adGsFTAosqPk#{rand(999)}"
    john = "john-#{rand(999)}"
    assert_equal(btc, addresses.acquire(john) { btc })
    assert(btc != addresses.acquire(john, lifetime: 0) { "32wtFfKbjWHpu9WFzX9adGSSTAosqPk#{rand(999)}" })
  end
end
