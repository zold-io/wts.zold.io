# frozen_string_literal: true

# SPDX-FileCopyrightText: Copyright (c) 2018-2026 Zerocracy
# SPDX-License-Identifier: MIT

require 'openssl'
require 'zold/key'
require_relative '../objects/keygap'
require_relative 'test__helper'

class WTS::KeygapTest < Minitest::Test
  def test_extracts_and_merges_back
    (10..30).each do |length|
      pem, keygap = WTS::Keygap.new.extract(Zold::Key.new(text: OpenSSL::PKey::RSA.new(2048).to_pem), length)
      assert_equal(length, keygap.length)
      refute_nil(WTS::Keygap.new.merge(pem, keygap))
    end
  end
end
