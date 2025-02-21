# SPDX-FileCopyrightText: Copyright (c) 2018-2025 Zerocracy
# SPDX-License-Identifier: MIT

require 'minitest/autorun'
require 'webmock/minitest'
require_relative 'test__helper'
require_relative '../objects/receipts'

class WTS::ReceiptsTest < Minitest::Test
  def test_add_and_fetch
    WebMock.allow_net_connect!
    receipts = WTS::Receipts.new(t_pgsql, log: t_log)
    hash = 'abcdef'
    receipts.create('tester', hash, 'test')
    assert_equal('test', receipts.details(hash))
  end
end
