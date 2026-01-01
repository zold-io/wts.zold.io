# SPDX-FileCopyrightText: Copyright (c) 2018-2026 Zerocracy
# SPDX-License-Identifier: MIT

require 'tmpdir'
require 'zold/amount'
require 'zold/id'
require 'zold/remotes'
require 'zold/wallets'
require_relative '../objects/item'
require_relative '../objects/user'
require_relative 'test__helper'

class WTS::UserTest < Minitest::Test
  def test_creates
    WebMock.allow_net_connect!
    Dir.mktmpdir 'test' do |dir|
      wallets = Zold::Wallets.new(File.join(dir, 'wallets'))
      login = 'jeffrey08'
      user = WTS::User.new(
        login, WTS::Item.new(login, t_pgsql, log: t_log),
        wallets, log: t_log
      )
      user.create
      refute_predicate(user, :confirmed?)
      keygap = user.keygap
      user.confirm(keygap)
      assert_predicate(user, :confirmed?)
    end
  end
end
