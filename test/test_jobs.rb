# SPDX-FileCopyrightText: Copyright (c) 2018-2025 Zerocracy
# SPDX-License-Identifier: MIT

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
