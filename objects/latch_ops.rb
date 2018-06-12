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

#
# Operations that puts and remotes a file.
#
class LatchOps
  def initialize(file, ops)
    raise 'File can\'t be nil' if file.nil?
    @file = file
    raise 'Ops can\'t be nil' if ops.nil?
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
    @ops.push
  ensure
    stop
  end

  def pay(pass, bnf, amount, details)
    start
    @ops.pay(pass, bnf, amount, details)
  ensure
    stop
  end

  private

  def start
    FileUtils.mkdir_p(File.dirname(@file))
    FileUtils.touch(@file)
  end

  def stop
    FileUtils.rm_f(@file)
  end
end
