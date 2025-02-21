# SPDX-FileCopyrightText: Copyright (c) 2018-2025 Zerocracy
# SPDX-License-Identifier: MIT

require 'futex'
require 'fileutils'
require 'backtrace'
require 'zold/log'
require 'zold/age'
require_relative 'user_error'

#
# Job async.
#
class WTS::AsyncJob
  def initialize(job, pool, lock, log: Zold::Log::NULL)
    @job = job
    @pool = pool
    @lock = lock
    @log = log
  end

  def call(jid)
    FileUtils.mkdir_p(File.dirname(@lock))
    FileUtils.touch(@lock)
    @pool.post do
      Futex.new(@lock, lock: @lock, log: @log, timeout: 10 * 60).open do
        @job.call(jid)
      end
    rescue StandardError => e
      @log.error(Backtrace.new(e))
    end
  end
end
