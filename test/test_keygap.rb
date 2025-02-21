# SPDX-FileCopyrightText: Copyright (c) 2018-2025 Zerocracy
# SPDX-License-Identifier: MIT

require 'minitest/autorun'
require 'openssl'
require 'zold/key'
require_relative 'test__helper'
require_relative '../objects/keygap'

class WTS::KeygapTest < Minitest::Test
  def test_extracts_and_merges_back
    (10..30).each do |length|
      pvt = OpenSSL::PKey::RSA.new(2048)
      pem, keygap = WTS::Keygap.new.extract(Zold::Key.new(text: pvt.to_pem), length)
      assert_equal(length, keygap.length)
      key = WTS::Keygap.new.merge(pem, keygap)
      assert(!key.nil?)
    end
  end
end
