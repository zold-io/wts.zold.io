# SPDX-FileCopyrightText: Copyright (c) 2018-2025 Zerocracy
# SPDX-License-Identifier: MIT

require 'futex'

#
# Exclusive job.
#
class WTS::ExclusiveJob
  def initialize(job, lock, log: Zold::Log::NULL)
    @job = job
    @lock = lock
    @log = log
  end

  def call(jid)
    Futex.new(@lock, lock: @lock, log: @log, timeout: 60 * 60).open do
      @job.call(jid)
    end
  end
end
