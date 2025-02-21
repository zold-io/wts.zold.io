# SPDX-FileCopyrightText: Copyright (c) 2018-2025 Zerocracy
# SPDX-License-Identifier: MIT

require 'minitest/autorun'
require 'webmock/minitest'
require_relative 'test__helper'
require_relative '../objects/tokens'

class WTS::TokensTest < Minitest::Test
  def test_sets_and_resets
    WebMock.allow_net_connect!
    tokens = WTS::Tokens.new(t_pgsql, log: t_log)
    login = "jeff#{rand(999)}"
    item = WTS::Item.new(login, t_pgsql, log: t_log)
    item.create(Zold::Id.new, Zold::Key.new(text: OpenSSL::PKey::RSA.new(2048).to_pem))
    before = tokens.get(login)
    assert(!before.nil?)
    assert_equal(before, tokens.get(login))
    after = tokens.reset(login)
    assert(before != after)
    assert(tokens.reset(login) != after)
  end
end
