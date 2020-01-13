# Copyright (c) 2018-2020 Zerocracy, Inc.
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
