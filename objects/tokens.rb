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
require 'securerandom'
require_relative 'user_error'

#
# Tokens of users.
#
class WTS::Tokens
  def initialize(pgsql, log: Zold::Log::NULL)
    @pgsql = pgsql
    @log = log
  end

  # API token, if exists. Otherwise, resets it.
  def get(login)
    row = @pgsql.exec('SELECT token FROM token WHERE login = $1', [login])[0]
    return row['token'] unless row.nil?
    reset(login)
  end

  # Sets a new API token to the user.
  def reset(login)
    token = SecureRandom.uuid.gsub(/[^a-f0-9]/, '')
    @pgsql.exec(
      'INSERT INTO token (login, token) VALUES ($1, $2) ON CONFLICT (login) DO UPDATE SET token = $2',
      [login, token]
    )
    token
  end
end
