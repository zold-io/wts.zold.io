# SPDX-FileCopyrightText: Copyright (c) 2018-2025 Zerocracy
# SPDX-License-Identifier: MIT

require 'minitest/autorun'
require 'concurrent'
require 'tmpdir'
require_relative 'test__helper'
require_relative '../objects/async_job'
require_relative '../objects/safe_job'

class WTS::AsyncJobTest < Minitest::Test
  def test_simple_call
    pool = Concurrent::FixedThreadPool.new(16)
    latch = Concurrent::CountDownLatch.new(1)
    Dir.mktmpdir 'test' do |dir|
      job = proc { latch.count_down }
      lock = File.join(dir, 'lock')
      async = WTS::AsyncJob.new(WTS::SafeJob.new(job), pool, lock, log: t_log)
      async.call(1)
      latch.wait
      pool.shutdown
      pool.wait_for_termination
      assert(!File.exist?(lock))
    end
  end
end
