# Copyright (c) 2018-2020 Zold
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

# Receipts.
# Author:: Yegor Bugayenko (yegor256@gmail.com)
# Copyright:: Copyright (c) 2018 Yegor Bugayenko
# License:: MIT
class WTS::Receipts
  def initialize(pgsql, log: Zold::Log::NULL)
    @pgsql = pgsql
    @log = log
  end

  # Create new one
  def create(login, hash, details)
    id = @pgsql.exec(
      'INSERT INTO receipt (login, hash, details) VALUES ($1, $2, $3) RETURNING id',
      [login, hash, details]
    )[0]['id'].to_i
    @log.debug("New receipt #{id} generated")
    id
  end

  def details(hash)
    row = @pgsql.exec('SELECT details FROM receipt WHERE hash=$1', [hash])[0]
    raise WTS::UserError, "E225: Receipt not found by hash #{hash.inspect}" if row.nil?
    row['details']
  end
end
