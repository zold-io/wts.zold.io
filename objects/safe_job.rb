# Copyright (c) 2018-2024 Zerocracy
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
