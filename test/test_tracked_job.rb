# frozen_string_literal: true

# SPDX-FileCopyrightText: Copyright (c) 2018-2026 Zerocracy
# SPDX-License-Identifier: MIT

require_relative '../objects/jobs'
require_relative '../objects/tracked_job'
require_relative 'test__helper'

class WTS::TrackedJobTest < Minitest::Test
  def test_simple_call
    done = false
    WebMock.allow_net_connect!
    jobs = WTS::Jobs.new(t_pgsql, log: t_log)
    id = jobs.start('me')
    WTS::TrackedJob.new(proc { done = true }, jobs).call(id)
    assert_equal('OK', jobs.read(id))
  end
end
