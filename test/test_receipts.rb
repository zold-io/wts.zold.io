# frozen_string_literal: true

# SPDX-FileCopyrightText: Copyright (c) 2018-2026 Zerocracy
# SPDX-License-Identifier: MIT

require_relative '../objects/receipts'
require_relative 'test__helper'

class WTS::ReceiptsTest < Minitest::Test
  def test_add_and_fetch
    WebMock.allow_net_connect!
    receipts = WTS::Receipts.new(t_pgsql, log: t_log)
    hash = 'abcdef'
    receipts.create('tester', hash, 'test')
    assert_equal('test', receipts.details(hash))
  end
end
