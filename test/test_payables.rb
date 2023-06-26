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
require 'zold/remotes'
require 'zold/amount'
require_relative 'test__helper'
require_relative '../objects/payables'

class WTS::PayablesTest < Minitest::Test
  def test_add_and_fetch
    WebMock.disable_net_connect!
    Dir.mktmpdir 'test' do |dir|
      remotes = Zold::Remotes.new(file: File.join(dir, 'remotes.csv'))
      remotes.clean
      remotes.masters
      masters = remotes.all.take(2)
      remotes.all.each_with_index { |r, idx| remotes.remove(r[:host], r[:port]) if idx.positive? }
      wallets = %w[0000111122223333 ffffeeeeddddcccc 0123456701234567 9090909090909090 a1a1a1a1a1a1a1a1]
      masters.each do |m|
        stub_request(:get, "http://#{m[:host]}:#{m[:port]}/wallets").to_return(
          body: wallets.join("\n")
        )
      end
      remotes.add('localhost', 444)
      masters.each do |m|
        remotes.add(m[:host], m[:port])
      end
      remotes.add('localhost', 123)
      masters.each do |m|
        wallets.each do |id|
          stub_request(:get, "http://#{m[:host]}:#{m[:port]}/wallet/#{id}").to_return(
            body: '{ "balance": 1234567, "txns": 5 }'
          )
        end
      end
      payables = WTS::Payables.new(t_pgsql, remotes, log: t_log)
      payables.discover
      assert_equal(wallets.count, payables.fetch.count)
      payables.update(max: wallets.count)
      payables.remove_banned
      assert_equal(Zold::Amount.new(zents: 1_234_567), payables.fetch[0][:balance])
      assert(payables.total >= wallets.count)
      assert(payables.balance > Zold::Amount::ZERO)
      assert(payables.txns >= wallets.count)
    end
  end
end
