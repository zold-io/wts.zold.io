# Copyright (c) 2018-2023 Zerocracy
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
require 'time'
require_relative 'user_error'

#
# Feature toggles.
#
class WTS::Toggles
  def initialize(pgsql, log: Zold::Log::NULL)
    @pgsql = pgsql
    @log = log
  end

  def set(key, value)
    if value.empty?
      @pgsql.exec('DELETE FROM toggle WHERE key = $1', [key])
    else
      @pgsql.exec(
        [
          'INSERT INTO toggle (key, value)',
          'VALUES ($1, $2)',
          'ON CONFLICT (key) DO UPDATE SET value = $2, updated = NOW()'
        ].join(' '),
        [key, value]
      )
    end
  end

  def get(key, default = '')
    r = @pgsql.exec('SELECT value FROM toggle WHERE key = $1', [key])[0]
    return default if r.nil?
    r['value']
  end

  def list
    @pgsql.exec('SELECT * FROM toggle ORDER BY key').map do |r|
      {
        key: r['key'],
        value: r['value'],
        updated: Time.parse(r['updated'])
      }
    end
  end
end
