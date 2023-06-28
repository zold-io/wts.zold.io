# Copyright (c) 2018-2023 Zerocracy
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
require_relative '../objects/toggles'

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
