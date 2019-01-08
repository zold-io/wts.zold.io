# Copyright (c) 2018-2019 Zerocracy, Inc.
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
require 'backtrace'
require 'zold/log'
require 'zold/age'
require_relative 'user_error'

#
# Job async.
#
class AsyncJob
  def initialize(job, pool, lock, log: Zold::Log::NULL)
    @job = job
    @pool = pool
    @lock = lock
    @log = log
  end

  def call
    begin
      Futex.new(@lock, timeout: 0, lock: @lock, log: @log).open
    rescue Futex::CantLock => e
      raise UserError, "Another operation is still running at #{@lock} for #{Zold::Age.new(e.start)}, try again later"
    end
    @pool.post do
      Futex.new(@lock, lock: @lock, log: @log).open do
        @job.call
      end
      FileUtils.rm(@lock)
    rescue StandardError => e
      @log.error(Backtrace.new(e))
    end
  end
end
