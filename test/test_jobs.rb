# Copyright (c) 2018-2022 Zold
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
require_relative '../objects/jobs'

class WTS::JobsTest < Minitest::Test
  def test_saves_and_reads
    WebMock.allow_net_connect!
    jobs = WTS::Jobs.new(t_pgsql, log: t_log)
    id = jobs.start('tester')
    assert_equal('Running', jobs.read(id))
    assert_equal('Running', jobs.status(id))
    jobs.update(id, 'well...')
    assert_equal('well...', jobs.read(id))
    jobs.update(id, 'OK')
    assert_equal('OK', jobs.read(id))
    assert_equal('OK', jobs.status(id))
  end

  def test_saves_and_reads_results
    WebMock.allow_net_connect!
    jobs = WTS::Jobs.new(t_pgsql, log: t_log)
    id = jobs.start('tester')
    jobs.result(id, 'foo', 'hello!')
    jobs.result(id, 'bar', 'Hm...')
    jobs.result(id, 'bar', 'Bye!')
    assert_equal('Bye!', jobs.results(id)['bar'])
  end
end
