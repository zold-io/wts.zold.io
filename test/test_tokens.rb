# frozen_string_literal: true

# SPDX-FileCopyrightText: Copyright (c) 2018-2026 Zerocracy
# SPDX-License-Identifier: MIT

require_relative '../objects/tokens'
require_relative 'test__helper'

class WTS::TokensTest < Minitest::Test
  def test_sets_and_resets
    WebMock.allow_net_connect!
    tokens = WTS::Tokens.new(t_pgsql, log: t_log)
    login = "jeff#{rand(999)}"
    WTS::Item.new(login, t_pgsql, log: t_log).create(Zold::Id.new, Zold::Key.new(text: OpenSSL::PKey::RSA.new(2048).to_pem))
    before = tokens.get(login)
    refute_nil(before)
    assert_equal(before, tokens.get(login))
    after = tokens.reset(login)
    refute_equal(before, after)
    refute_equal(tokens.reset(login), after)
  end
end
