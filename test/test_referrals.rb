# SPDX-FileCopyrightText: Copyright (c) 2018-2025 Zerocracy
# SPDX-License-Identifier: MIT

require 'minitest/autorun'
require 'webmock/minitest'
require_relative 'test__helper'
require_relative '../objects/wts'
require_relative '../objects/referrals'

class WTS::ReferralsTest < Minitest::Test
  def test_register_and_fetch
    WebMock.disable_net_connect!
    referrals = WTS::Referrals.new(t_pgsql, log: t_log)
    login = 'yegor256'
    referrals.register(login, 'friend', source: nil)
    assert(referrals.exists?(login))
    assert_equal('friend', referrals.ref(login))
  end

  def test_encrypts_and_decrypts
    crypt = WTS::Referrals::Crypt.new
    ['yegor256-2', '', 'abc'].each do |login|
      enc = crypt.encode(login)
      assert_equal(login, crypt.decode(enc))
    end
  end
end
