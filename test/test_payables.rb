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
require 'zold/remotes'
require 'zold/amount'
require_relative 'test__helper'
require_relative '../objects/pgsql'
require_relative '../objects/payables'

class PayablesTest < Minitest::Test
  def test_add_and_fetch
    WebMock.disable_net_connect!
    Dir.mktmpdir 'test' do |dir|
      remotes = Zold::Remotes.new(file: File.join(dir, 'remotes.csv'))
      remotes.clean
      stub_request(:get, 'http://b2.zold.io:4096/wallets').to_return(
        status: 200, body: '0000111122223333'
      )
      remotes.add('b2.zold.io', 4096)
      stub_request(:get, 'http://b2.zold.io:4096/wallet/0000111122223333/balance').to_return(
        status: 200, body: '1234567'
      )
      payables = Payables.new(Pgsql::TEST.start, remotes, log: test_log)
      payables.discover
      assert_equal(1, payables.fetch.count)
      payables.update
      payables.remove_banned
      assert_equal(Zold::Amount.new(zents: 1_234_567), payables.fetch[0][:balance])
      assert(payables.total >= 1)
      assert(payables.balance > Zold::Amount::ZERO)
    end
  end
end
