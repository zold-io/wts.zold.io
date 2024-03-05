# Copyright (c) 2018-2024 Zerocracy
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
# Job that updates remotes before letting the original Job do the work.
#
class WTS::UpdateJob
  def initialize(job, remotes, log: Zold::Log::NULL, network: 'test')
    @job = job
    @remotes = remotes
    @log = log
    @network = network
  end

  def call(jid)
    cmd = Zold::Remote.new(remotes: @remotes, log: @log)
    args = ['remote', "--network=#{@network}"]
    if @network == Zold::Wallet::MAINET
      @log.info('Updating remotes before running the job...')
      cmd.run(args + ['trim'])
      cmd.run(args + ['masters'])
      cmd.run(args + ['reset']) if @remotes.all.empty?
      cmd.run(args + ['update', '--depth=3'])
      cmd.run(args + ['select'])
    else
      cmd.run(args + ['clean'])
    end
    @job.call(jid)
  end
end
