# Copyright (c) 2018-2019 Zerocracy, Inc.
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
require_relative '../objects/ticks'
require_relative '../objects/graph'

class WTS::GraphTest < Minitest::Test
  def test_renders_svg
    WebMock.allow_net_connect!
    ticks = WTS::Ticks.new(test_pgsql, log: test_log)
    ticks.add('Price' => 1, 'time' => tme(-1))
    ticks.add('Price' => 3, 'time' => tme(-2))
    ticks.add('Price' => 2, 'time' => tme(-10))
    ticks.add('Price' => 1.5, 'time' => tme(-14))
    ticks.add('Price' => 1.2, 'time' => tme(-50))
    FileUtils.mkdir_p('target')
    IO.write('target/graph.svg', WTS::Graph.new(ticks, log: test_log).svg(['Price'], 1, 0))
  end

  private

  def tme(days)
    ((Time.now.to_f + days * 24 * 60 * 60) * 1000).to_i
  end
end
