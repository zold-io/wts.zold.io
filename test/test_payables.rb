# SPDX-FileCopyrightText: Copyright (c) 2018-2025 Zerocracy
# SPDX-License-Identifier: MIT

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
