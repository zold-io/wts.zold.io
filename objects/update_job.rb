# frozen_string_literal: true

# SPDX-FileCopyrightText: Copyright (c) 2018-2026 Zerocracy
# SPDX-License-Identifier: MIT

require 'loog'
require 'zold/commands/remote'

class WTS::UpdateJob
  def initialize(job, remotes, log: Loog::NULL, network: 'test')
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
