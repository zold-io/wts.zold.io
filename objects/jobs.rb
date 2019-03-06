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

require 'zold/log'
require 'securerandom'
require_relative 'pgsql'
require_relative 'user_error'

#
# Background jobs.
#
class Jobs
  def initialize(pgsql, log: Log::NULL)
    @pgsql = pgsql
    @log = log
  end

  # Does it exist?
  def exists?(id)
    !@pgsql.exec('SELECT * FROM job WHERE id = $1', [id]).empty?
  end

  # Start a new job and return its ID
  def start(login)
    @pgsql.exec(
      'UPDATE job SET log = $1 WHERE started < NOW() - INTERVAL \'1 HOURS\'',
      ['We are sorry, but most probably the job is lost; try again...']
    )
    uuid = SecureRandom.uuid
    @pgsql.exec('INSERT INTO job (id, log, login) VALUES ($1, $2, $3)', [uuid, 'Running', login])
    uuid
  end

  # Read the Job result (OK, or backtrace or 'Running')
  def read(id)
    rows = @pgsql.exec('SELECT log FROM job WHERE id = $1', [id])
    raise UserError, "Job #{id} not found" if rows.empty?
    rows[0]['log']
  end

  # Update the log
  def update(id, log)
    @pgsql.exec('UPDATE job SET log = $2 WHERE id = $1', [id, log])
  end

  # Read the Job full output
  def output(id)
    rows = @pgsql.exec('SELECT output FROM job WHERE id = $1', [id])
    raise UserError, "Job #{id} not found" if rows.empty?
    rows[0]['output']
  end
end
