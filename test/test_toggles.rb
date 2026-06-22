# frozen_string_literal: true

# SPDX-FileCopyrightText: Copyright (c) 2018-2026 Zerocracy
# SPDX-License-Identifier: MIT

require_relative '../objects/toggles'
require_relative 'test__helper'

class WTS::TogglesTest < Minitest::Test
  def test_sets_and_gets
    WebMock.allow_net_connect!
    toggles = WTS::Toggles.new(t_pgsql, log: t_log)
    key = 'hey'
    assert_equal('', toggles.get(key))
    toggles.set(key, 'hello, world!')
    assert_equal('hello, world!', toggles.get(key))
    toggles.set(key, 'bye')
    assert_equal('bye', toggles.get(key))
    toggles.set(key, '')
    assert_equal('the default', toggles.get(key, 'the default'))
  end
end
