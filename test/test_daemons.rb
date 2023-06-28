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
require_relative '../objects/daemons'

class WTS::DaemonsTest < Minitest::Test
  def test_start_and_stop
    WebMock.allow_net_connect!
    daemons = WTS::Daemons.new(t_pgsql, log: t_log)
    started = false
    daemons.start('test', 0, pause: 0) do
      started = true
    end
    sleep 0.1
    assert(started)
  end

  def test_start_and_run_a_broken_thread
    WebMock.allow_net_connect!
    daemons = WTS::Daemons.new(t_pgsql, log: t_log)
    stepped = 0
    daemons.start('test-errors', 0, pause: 0) do
      stepped += 1
      raise StandardError, 'Intended' if stepped == 1
    end
    sleep 0.1
    assert(stepped > 1)
  end
end
