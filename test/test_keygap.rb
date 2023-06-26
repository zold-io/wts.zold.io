# Copyright (c) 2018-2023 Zold
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the 'Software'), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED 'AS IS', WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

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
