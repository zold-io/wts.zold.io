# Copyright (c) 2018-2021 Zold
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
require_relative 'wts'
require_relative 'user_error'

#
# Tags of a user.
#
class WTS::Tags
  def initialize(login, pgsql, log: Zold::Log::NULL)
    @login = login
    @pgsql = pgsql
    @log = log
  end

  # This tag exists?
  def exists?(tag)
    !@pgsql.exec('SELECT * FROM tag WHERE login = $1 and name = $2', [@login, tag]).empty?
  end

  # Add tag.
  def attach(tag)
    raise WTS::UserError, "E181: Invalid tag #{tag.inspect}" unless /^[a-z0-9-]+$/.match?(tag)
    @pgsql.exec('INSERT INTO tag (login, name) VALUES ($1, $2)', [@login, tag])
  end
end
