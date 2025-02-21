# SPDX-FileCopyrightText: Copyright (c) 2018-2025 Zerocracy
# SPDX-License-Identifier: MIT

require 'zold/commands/fetch'
require 'backtrace'

#
# Job that reports its result to SQL.
#
class WTS::TrackedJob
  def initialize(job, jobs)
    @job = job
    @jobs = jobs
  end

  def call(jid)
    @job.call(jid)
    @jobs.update(jid, 'OK')
  rescue Zold::Fetch::NotFound => e
    @jobs.result(jid, 'error_message', e.message)
    @jobs.update(jid, e.message + "; most probably your wallet is lost by Zold network; \
it is recommended to log in to wts.zold.io and click Restart at the top menu; a new wallet \
will be created and this error will go away")
  rescue StandardError => e
    @jobs.result(jid, 'error_message', e.message)
    @jobs.update(jid, Backtrace.new(e).to_s)
    raise e
  end
end
