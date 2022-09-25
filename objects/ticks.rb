# Copyright (c) 2018-2022 Zold
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
require_relative 'user_error'

#
# Ticks in AWS DynamoDB.
#
class WTS::Ticks
  def initialize(pgsql, log: Zold::Log::NULL)
    @pgsql = pgsql
    @log = log
  end

  # Already exists for the current time?
  def exists?(key, seconds = 6 * 60 * 60)
    !@pgsql.exec(
      "SELECT FROM tick WHERE key = $1 AND created > NOW() - INTERVAL \'#{seconds} SECONDS\'",
      [key]
    ).empty?
  end

  # Add ticks.
  def add(hash)
    hash.each do |k, v|
      @pgsql.exec('INSERT INTO tick (key, value) VALUES ($1, $2)', [k, v])
    end
  end

  # Fetch them all.
  def fetch(key)
    @pgsql.exec('SELECT * FROM tick WHERE key = $1', [key]).map do |r|
      { key: r['key'], value: r['value'].to_f, created: Time.parse(r['created']) }
    end
  end

  # Fetch the latest.
  def latest(key)
    row = @pgsql.exec('SELECT * FROM tick WHERE key = $1 ORDER BY created DESC LIMIT 1', [key])[0]
    raise WTS::UserError, "E182: No ticks found for #{key}" if row.nil?
    row['value'].to_f
  end
end
