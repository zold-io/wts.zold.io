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
require_relative 'wts'
require_relative 'user_error'

#
# Daemons.
#
class WTS::Daemons
  def initialize(pgsql, log: Zold::Log::NULL)
    @pgsql = pgsql
    @log = log
    @threads = {}
  end

  def start(id, seconds = 60, pause: 5)
    @threads[id] = Thread.new do
      sleep(pause) # to let the main script load all Ruby methods
      loop do
        sleep((seconds - age(id)).clamp(0, 5 * 60))
        next if age(id) < seconds
        begin
          yield
        rescue WTS::UserError => e
          @log.error(Backtrace.new(e))
        rescue Exception => e
          Raven.capture_exception(e)
          @log.error(Backtrace.new(e))
        end
        @pgsql.exec('INSERT INTO daemon (id) VALUES ($1) ON CONFLICT (id) DO UPDATE SET executed = NOW()', [id])
      rescue Exception
        # If we reach this point, we must not even try to
        # do anything. Here we must quietly ignore everything
        # and let the daemon go to the next cycle.
      end
    end
  end

  private

  # The age of the daemon in seconds, or zero if not yet found
  def age(id)
    row = @pgsql.exec('SELECT executed FROM daemon WHERE id = $1', [id])[0]
    return 10_000_000_000 if row.nil?
    Time.now - Time.parse(row['executed'])
  end
end
