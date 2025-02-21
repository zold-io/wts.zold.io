# SPDX-FileCopyrightText: Copyright (c) 2018-2025 Zerocracy
# SPDX-License-Identifier: MIT

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
