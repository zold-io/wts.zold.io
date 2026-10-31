# frozen_string_literal: true

# SPDX-FileCopyrightText: Copyright (c) 2018-2026 Zerocracy
# SPDX-License-Identifier: MIT

require_relative '../objects/dollars'
require_relative 'test__helper'

class WTS::DollarsTest < Minitest::Test
  def test_keeps_cents_above_hundred
    assert_equal('$1,234,150.51', WTS::Dollars.new(1_234_150.51).to_s, 'Cents must not be dropped')
  end

  def test_keeps_cents_below_hundred
    assert_equal('$99.99', WTS::Dollars.new(99.99).to_s, 'Cents must not be dropped')
  end
end
