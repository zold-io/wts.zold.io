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

require 'parallelize'
require 'backtrace'
require 'zold/key'
require 'zold/id'
require 'zold/commands/push'
require 'zold/commands/remote'
require_relative 'stats'
require_relative 'pool'
require_relative 'pmnts'
require_relative 'air'
require_relative '../version'

#
# The stress tester.
#
class Stress
  # Number of wallets to work with
  POOL_SIZE = 8

  def initialize(id:, pub:, pvt:, wallets:, remotes:, copies:, log: Zold::Log::Quiet.new)
    @id = id
    @pub = pub
    @pvt = pvt
    @wallets = wallets
    @remotes = remotes
    @copies = copies
    @log = log
    @stats = Stats.new(log: log)
    @air = Air.new
  end

  def to_json
    {
      'version': VERSION,
      'remotes': @remotes.all.count,
      'wallets': @wallets.all.map do |id|
        @wallets.find(id) do |w|
          {
            'id': w.id,
            'txns': w.txns.count,
            'balance': w.balance.to_zld(4)
          }
        end
      end,
      'thread': @thread ? @thread.status : '-',
      'air': @air.to_json
    }.merge(@stats.to_json)
  end

  def run(delay: 60, cycles: -1, opts: [])
    cycle = 0
    @log.info("Stress thread started, delay=#{delay}, cycles=#{cycles}")
    loop do
      @stats.exec('cycle') do
        one_cycle(opts)
      end
      sleep(delay)
      cycle += 1
      break if cycles.positive? && cycle >= cycles
    end
    @log.info("Stress thread finished after cycle no.#{cycle}")
  end

  private

  def one_cycle(opts)
    update(opts)
    pool = Pool.new(
      id: @id, pub: @pub, wallets: @wallets,
      remotes: @remotes, copies: @copies, stats: @stats,
      log: @log
    )
    pool.rebuild(Stress::POOL_SIZE, opts)
    @log.info("There are #{@wallets.all.count} wallets in the pool after rebuild")
    @wallets.all.peach(Concurrent.processor_count * 8) do |id|
      Zold::Push.new(wallets: @wallets, remotes: @remotes, log: @log).run(
        ['push', id.to_s] + opts
      )
    end
    sent = Pmnts.new(
      pvt: @pvt, wallets: @wallets,
      remotes: @remotes, stats: @stats,
      log: @log
    ).send
    @log.info("#{sent.count} payments have been sent")
    mutex = Mutex.new
    sent.group_by { |p| p[:source] }.peach(Concurrent.processor_count * 8) do |a|
      @stats.exec('push') do
        Zold::Push.new(wallets: @wallets, remotes: @remotes, log: @log).run(
          ['push', a[0].to_s] + opts
        )
        mutex.synchronize do
          a[1].each { |p| @air.add(p) }
        end
      end
    end
    @log.info("#{@air.fetch.count} payments are now in the air")
    @air.fetch.group_by { |p| p[:target] }.each do |a|
      if @wallets.find(a[0], &:exists?)
        Zold::Remove.new(wallets: @wallets, log: @log).run(
          ['remove', a[0].to_s]
        )
      end
      @stats.exec('pull') do
        Zold::Pull.new(wallets: @wallets, remotes: @remotes, copies: @copies, log: @log).run(
          ['pull', a[0].to_s] + opts
        )
      end
    end
    @log.info("There are #{@wallets.all.count} wallets in the pool after re-pull")
    @air.fetch.each do |p|
      next unless @wallets.find(p[:target], &:exists?)
      t = @wallets.find(p[:target], &:txns).find { |x| x.details == p[:details] && x.bnf == p[:source] }
      next if t.nil?
      @stats.put('arrived', Time.now - p[:start])
      @log.info("Payment arrived to #{p[:target]} at ##{t.id} in #{Zold::Age.new(p[:start])}: #{t.details}")
      @air.delete(p)
    end
    @log.info("#{@air.fetch.count} payments are still in the air")
  end

  def update(opts)
    return if opts.include?('--network=test')
    cmd = Zold::Remote.new(remotes: @remotes, log: @log)
    args = ['remote'] + opts
    cmd.run(args + ['trim'])
    cmd.run(args + ['reset']) if @remotes.all.empty?
    cmd.run(args + ['update'])
    cmd.run(args + ['select'])
  end
end
