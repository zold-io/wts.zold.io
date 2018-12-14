# Copyright (c) 2018 Yegor Bugayenko
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
require_relative 'user_error'

#
# Operations with a user, async.
#
class AsyncOps
  def initialize(pool, ops, lock)
    @pool = pool
    @ops = ops
    @lock = lock
  end

  def pull
    exec { @ops.pull }
  end

  def push
    exec { @ops.push }
  end

  def pay(keygap, bnf, amount, details)
    exec { @ops.pay(keygap, bnf, amount, details) }
  end

  private

  def exec
    @pool.post do
      Futex.new(@lock, timeout: 1).open do
        @ops.pull
      end
    rescue Futex::CantLock
      raise UserError, 'Another operation is still running, try again later'
    end
  end
end
