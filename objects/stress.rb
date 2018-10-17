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
require_relative '../version'

#
# The stress tester.
#
class Stress
  # Number of wallets to work with
  POOL_SIZE = 8

  def initialize(id:, pub:, pvt:, wallets:, remotes:, copies:, log: Zold::Log::Quiet.new)
    raise 'Wallet ID can\'t be nil' if id.nil?
    raise 'Wallet ID must be of type Id' unless id.is_a?(Zold::Id)
    @id = id
    raise 'Public RSA key can\'t be nil' if pub.nil?
    raise 'Public RSA key must be of type Key' unless pub.is_a?(Zold::Key)
    @pub = pub
    raise 'Private RSA key can\'t be nil' if pvt.nil?
    raise 'Private RSA key must be of type Key' unless pvt.is_a?(Zold::Key)
    @pvt = pvt
    raise 'Wallets can\'t be nil' if wallets.nil?
    @wallets = wallets
    raise 'Remotes can\'t be nil' if remotes.nil?
    @remotes = remotes
    raise 'Copies can\'t be nil' if copies.nil?
    @copies = copies
    raise 'Log can\'t be nil' if log.nil?
    @log = log
    @stats = Stats.new
    %w[arrived paid pull_ok pull_errors push_ok push_errors].each do |m|
      @stats.announce(m)
    end
    @start = Time.now
    @waiting = []
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
      'waiting': @waiting,
      'alive_hours': (Time.now - @start) / (60 * 60)
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
    sent = Pmnts.new(
      id: @id, pub: @pub, wallets: @wallets,
      remotes: @remotes, copies: @copies, stats: @stats,
      log: @log
    ).send
    @waiting.push(sent).flatten
    sent.peach(Concurrent.processor_count * 8) do |p|
      @stats.exec('push') do
        Zold::Push.new(wallets: @wallets, remotes: @remotes, log: @log).run(
          ['push', p[:source].to_s] + opts
        )
      end
    end
    pool.repull(opts)
    @waiting.each do |p|
      t = @wallets.find(p[:target], &:txns).find { |t| t.details == p[:details] && t.bnf == p[:source] }
      next if t.nil?
      @stats.put('arrived', Time.now - p[:start])
      @log.info("Payment arrived to #{p[:target]} at ##{t.id} in #{Zold::Age.new(p[:start])}: #{t.details}")
      @waiting.delete(p)
    end
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
