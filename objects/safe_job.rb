# SPDX-FileCopyrightText: Copyright (c) 2018-2025 Zerocracy
# SPDX-License-Identifier: MIT

require 'raven'
require 'backtrace'
require 'zold/log'
require_relative 'user_error'

#
# Job that log exceptions.
#
class WTS::SafeJob
  def initialize(job, log: Zold::Log::NULL, telepost: Telepost::Fake.new)
    @log = log
    @job = job
    @telepost = telepost
  end

  def call(jid)
    @job.call(jid)
  rescue WTS::UserError => e
    @log.error(Backtrace.new(e).to_s)
  rescue StandardError => e
    @log.error(Backtrace.new(e).to_s)
    @telepost.spam(
      "⚠️ There is an unrecoverable error `#{e.class.name}`",
      "in the job [#{jid}](https://wts.zold.io/output?id=#{jid}):",
      "`#{e.message.inspect}`",
      "\n\nYou may want to investigate and fix it as soon as possible!"
    )
    Raven.capture_exception(e)
  end
end
