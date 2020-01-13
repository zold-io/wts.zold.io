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

require 'zold/log'
require_relative 'user_error'

#
# Mobile codes.
#
class WTS::Mcodes
  def initialize(pgsql, log: Zold::Log::NULL)
    @pgsql = pgsql
    @log = log
  end

  def exists?(phone)
    !@pgsql.exec('SELECT code FROM mcode WHERE phone = $1', [phone]).empty?
  end

  def set(phone, code)
    raise "Code must be over 1000: #{code}" if code < 1000
    raise "Code must be less than 10000: #{code}" if code > 9999
    @pgsql.exec('INSERT INTO mcode (phone, code) VALUES ($1, $2)', [phone, code])
  end

  def get(phone)
    r = @pgsql.exec('SELECT code FROM mcode WHERE phone = $1', [phone])[0]
    raise WTS::UserError, "EThere is not the code associated with #{phone}" if r.nil?
    r['code'].to_i
  end

  def remove(phone)
    @pgsql.exec('DELETE FROM mcode WHERE phone = $1', [phone])
  end
end
