# Copyright (c) 2018-2023 Zerocracy
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
require 'tmpdir'
require 'zold/amount'
require 'zold/wallets'
require 'zold/remotes'
require 'zold/id'
require_relative 'test__helper'
require_relative '../objects/user'
require_relative '../objects/ops'
require_relative '../objects/item'

class WTS::OpsTest < Minitest::Test
  def test_make_payment
    WebMock.allow_net_connect!
    Dir.mktmpdir 'test' do |dir|
      wallets = Zold::Wallets.new(File.join(dir, 'wallets'))
      remotes = Zold::Remotes.new(file: File.join(dir, 'remotes.csv'))
      remotes.clean
      login = 'jeff0192'
      item = WTS::Item.new(login, t_pgsql, log: t_log)
      user = WTS::User.new(login, item, wallets, log: t_log)
      user.create
      keygap = user.keygap
      user.confirm(keygap)
      friend = WTS::User.new(
        'friend033',
        WTS::Item.new('friend033', t_pgsql, log: t_log),
        wallets, log: t_log
      )
      friend.create
      # copies = File.join(dir, 'copies')
      # WTS::Ops.new(item, user, wallets, remotes, copies, log: t_log).pay(
      #   keygap, friend.item.id, Zold::Amount.new(zld: 19.99), 'for fun'
      # )
    end
  end
end
