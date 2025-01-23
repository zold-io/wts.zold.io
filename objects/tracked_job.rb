# Copyright (c) 2018-2025 Zerocracy
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
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

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
