# Copyright (c) 2018-2025 Zerocracy
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
require 'webmock/minitest'
require_relative 'test__helper'
require_relative '../objects/wts'
require_relative '../objects/referrals'

class WTS::ReferralsTest < Minitest::Test
  def test_register_and_fetch
    WebMock.disable_net_connect!
    referrals = WTS::Referrals.new(t_pgsql, log: t_log)
    login = 'yegor256'
    referrals.register(login, 'friend', source: nil)
    assert(referrals.exists?(login))
    assert_equal('friend', referrals.ref(login))
  end

  def test_encrypts_and_decrypts
    crypt = WTS::Referrals::Crypt.new
    ['yegor256-2', '', 'abc'].each do |login|
      enc = crypt.encode(login)
      assert_equal(login, crypt.decode(enc))
    end
  end
end
