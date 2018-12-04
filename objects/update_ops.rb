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

require 'zold/log'
require 'zold/commands/remote'

#
# Operations that update remotes before and after.
#
class UpdateOps
  def initialize(ops, remotes, log: Zold::Log::NULL, network: 'test')
    raise 'Ops can\'t be nil' if ops.nil?
    @ops = ops
    raise 'Remotes can\'t be nil' if remotes.nil?
    @remotes = remotes
    raise 'Log can\'t be nil' if log.nil?
    @log = log
    raise 'Network can\'t be nil' if network.nil?
    @network = network
  end

  def pull
    update
    @ops.pull
    update
  end

  def push
    update
    @ops.push
    update
  end

  def pay(keygap, bnf, amount, details)
    update
    @ops.pay(keygap, bnf, amount, details)
    update
  end

  private

  def update
    cmd = Zold::Remote.new(remotes: @remotes, log: @log)
    args = ['remote', "--network=#{@network}"]
    cmd.run(args + ['trim'])
    cmd.run(args + ['reset']) if @remotes.all.empty?
    return if @remotes.all.count >= 8 && @remotes.all.find { |r| r[:score] >= Zold::Tax::EXACT_SCORE }
    cmd.run(args + ['update'])
    cmd.run(args + ['select'])
  end
end
