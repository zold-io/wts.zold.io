# frozen_string_literal: true

# SPDX-FileCopyrightText: Copyright (c) 2018-2026 Zerocracy
# SPDX-License-Identifier: MIT

require_relative '../objects/referrals'
require_relative '../objects/wts'
require_relative 'test__helper'

class WTS::ReferralsTest < Minitest::Test
  def test_register_and_fetch
    WebMock.disable_net_connect!
    referrals = WTS::Referrals.new(t_pgsql, log: t_log)
    login = 'yegor256'
    referrals.register(login, 'friend', source: nil)
    assert(referrals.exists?(login))
    assert_equal('friend', referrals.ref(login))
  end

  def test_finds_referral_for_plain_logins
    referrals = WTS::Referrals.new(t_pgsql, log: t_log)
    %w[99problems a].each do |login|
      referrals.register(login, 'friend')
      assert_equal('friend', referrals.ref(login))
    end
  end

  def test_decodes_invalid_aliases
    crypt = WTS::Referrals::Crypt.new
    ['', 'a', '99problems', "#{WTS::Referrals::Crypt::ENCODINGS.count}user"].each do |login|
      assert_equal(login, crypt.decode(login))
    end
  end

  def test_encrypts_and_decrypts
    crypt = WTS::Referrals::Crypt.new
    ['yegor256-2', '', 'abc'].each do |login|
      assert_equal(login, crypt.decode(crypt.encode(login)))
    end
  end
end
