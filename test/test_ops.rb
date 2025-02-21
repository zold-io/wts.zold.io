# SPDX-FileCopyrightText: Copyright (c) 2018-2025 Zerocracy
# SPDX-License-Identifier: MIT

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
