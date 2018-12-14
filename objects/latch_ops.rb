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

require_relative 'atomic_file'

#
# Operations that puts and remotes a file.
#
class LatchOps
  def initialize(file, ops)
    @file = file
    @ops = ops
  end

  def pull
    start
    @ops.pull
  ensure
    stop
  end

  def push
    start
    yield @ops if block_given?
    @ops.push
  ensure
    stop
  end

  def pay(keygap, bnf, amount, details)
    start
    @ops.pay(keygap, bnf, amount, details)
  ensure
    stop
  end

  def counter
    read_counter
  end

  private

  def start
    counter = read_counter
    counter += 1
    AtomicFile.new(@file).write(counter)
  end

  def read_counter
    AtomicFile.new(@file).read.to_i
  end

  def stop
    counter = read_counter
    counter -= 1
    AtomicFile.new(@file).write(counter)
  end
end
