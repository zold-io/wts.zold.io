# SPDX-FileCopyrightText: Copyright (c) 2018-2025 Zerocracy
# SPDX-License-Identifier: MIT

require 'minitest/autorun'
require 'webmock/minitest'
require_relative 'test__helper'
require_relative '../objects/jobs'
require_relative '../objects/tracked_job'

class WTS::TrackedJobTest < Minitest::Test
  def test_simple_call
    done = false
    WebMock.allow_net_connect!
    jobs = WTS::Jobs.new(t_pgsql, log: t_log)
    id = jobs.start('me')
    job = WTS::TrackedJob.new(
      proc { done = true },
      jobs
    )
    job.call(id)
    assert_equal('OK', jobs.read(id))
  end
end
