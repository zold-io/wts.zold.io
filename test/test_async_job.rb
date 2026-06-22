# frozen_string_literal: true

# SPDX-FileCopyrightText: Copyright (c) 2018-2026 Zerocracy
# SPDX-License-Identifier: MIT

require 'concurrent'
require 'tmpdir'
require_relative '../objects/async_job'
require_relative '../objects/safe_job'
require_relative 'test__helper'

class WTS::AsyncJobTest < Minitest::Test
  def test_simple_call
    pool = Concurrent::FixedThreadPool.new(16)
    latch = Concurrent::CountDownLatch.new(1)
    Dir.mktmpdir('test') do |dir|
      lock = File.join(dir, 'lock')
      WTS::AsyncJob.new(WTS::SafeJob.new(proc { latch.count_down }), pool, lock, log: t_log).call(1)
      latch.wait
      pool.shutdown
      pool.wait_for_termination
      refute_path_exists(lock)
    end
  end
end
