# frozen_string_literal: true

# SPDX-FileCopyrightText: Copyright (c) 2018-2026 Zerocracy
# SPDX-License-Identifier: MIT

require 'tmpdir'
require 'zold/amount'
require 'zold/id'
require 'zold/remotes'
require 'zold/wallets'
require_relative '../objects/item'
require_relative '../objects/ops'
require_relative '../objects/user'
require_relative 'test__helper'

class WTS::OpsTest < Minitest::Test
  def test_make_payment
    WebMock.allow_net_connect!
    Dir.mktmpdir('test') do |dir|
      wallets = Zold::Wallets.new(File.join(dir, 'wallets'))
      Zold::Remotes.new(file: File.join(dir, 'remotes.csv')).clean
      login = 'jeff0192'
      user = WTS::User.new(login, WTS::Item.new(login, t_pgsql, log: t_log), wallets, log: t_log)
      user.create
      user.confirm(user.keygap)
      WTS::User.new('friend033', WTS::Item.new('friend033', t_pgsql, log: t_log), wallets, log: t_log).create
    end
  end
end
