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
require 'zold/tax'
require 'zold/commands/create'
require 'zold/commands/pull'
require 'zold/commands/push'
require 'zold/commands/pay'
require 'zold/commands/remote'
require 'zold/commands/taxes'
require 'zold/commands/remove'
require 'zold/verbose_thread'
require_relative 'stats'
require_relative 'pool'
require_relative '../version'

#
# The stress tester.
#
class Stress
  # Number of wallets to work with
  POOL_SIZE = 8

  # Amount to send in each payment
  AMOUNT = Zold::Amount.new(zld: 0.01)

  def initialize(id:, pub:, pvt:, wallets:, remotes:, copies:, network: 'test', log: Zold::Log::Quiet.new)
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
    raise 'Network can\'t be nil' if network.nil?
    @network = network
    raise 'Log can\'t be nil' if log.nil?
    @log = log
    @stats = Stats.new
    %w[arrived paid pull_ok pull_errors push_ok push_errors].each do |m|
      @stats.announce(m)
    end
    @start = Time.now
    @waiting = {}
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

  def start(delay: 60, cycles: -1)
    cycle = 0
    @thread = Thread.new do
      Zold::VerboseThread.new(@log).run do
        @log.info("Stress thread started, delay=#{delay}, cycles=#{cycles}")
        loop do
          @log.info("Stress thread cycle no.#{cycle} started")
          start = Time.now
          begin
            update
            @log.info("Updated remotes, #{@remotes.all.count} remained")
            Pool.new(
              id: @id, pub: @pub, wallets: @wallets,
              remotes: @remotes, copies: @copies, stats: @stats,
              network: @network, log: @log
            ).reload
            @log.info("Reloaded, #{@wallets.all.count} wallets in the pool")
            pay
            @log.info("Payments processed and pushed for #{@wallets.all.count} wallets")
            refetch
            @log.info("#{@wallets.all.count} wallets remained after re-fetch")
            match
            @stats.put('cycles_ok', Time.now - start)
            @log.info("Cycle no.#{cycle} finished in #{Zold::Age.new(start)}")
          rescue StandardError => e
            blame(e, start, 'cycle_errors')
            @log.info("Cycle no.#{cycle} failed in #{Zold::Age.new(start)}")
          end
          sleep(delay)
          cycle += 1
          break if cycles.positive? && cycle >= cycles
        end
        @log.info("Stress thread finished after cycle no.#{cycle}")
      end
    end
  end

  def update
    return unless @network == 'zold'
    cmd = Zold::Remote.new(remotes: @remotes, log: @log)
    args = ['remote', "--network=#{@network}"]
    cmd.run(args + ['trim'])
    cmd.run(args + ['reset']) if @remotes.all.empty?
    cmd.run(args + ['update'])
    cmd.run(args + ['select'])
  end

  def pay
    raise 'Too few wallets in the pool' if @wallets.all.count < 2
    start = Time.now
    @wallets.all.each do |source|
      amount = @wallets.find(source, &:balance) * (1.0 / (@wallets.all.count - 1))
      next if amount.zero?
      Tempfile.open do |f|
        File.write(f, @pvt.to_s)
        @wallets.all.each do |target|
          next if source == target
          pay_one(source, target, amount, f.path)
        end
      end
    end
    @wallets.all.peach(Concurrent.processor_count * 8) do |id|
      push(id)
    end
    @stats.put('pay_ok', Time.now - start)
  end

  def pay_one(source, target, amount, pvt)
    Zold::Taxes.new(wallets: @wallets, remotes: @remotes, log: @log).run(
      ['taxes', 'pay', source.to_s, "--network=#{@network}", "--private-key=#{pvt}", '--ignore-nodes-absence']
    )
    if @wallets.find(source) { |w| Zold::Tax.new(w).in_debt? }
      @log.error("The wallet #{source} is still in debt and we can't pay taxes")
      return
    end
    details = SecureRandom.uuid
    Zold::Pay.new(wallets: @wallets, remotes: @remotes, log: @log).run(
      ['pay', source.to_s, target.to_s, amount.to_zld, details, "--network=#{@network}", "--private-key=#{pvt}"]
    )
    @stats.put('paid', amount.to_zld.to_f)
    @waiting[details] = { start: Time.now, id: target }
  end

  def refetch
    start = Time.now
    @wallets.all.each do |id|
      Zold::Remove.new(wallets: @wallets, log: @log).run(
        ['remove', id.to_s]
      )
      pull(id)
    end
    @stats.put('refetch_ok', Time.now - start)
  end

  def match
    start = Time.now
    @wallets.all.each do |id|
      @wallets.find(id, &:txns).each do |t|
        next if t.amount.negative?
        arrival = @waiting[t.details]
        next unless arrival
        @stats.put('arrived', Time.now - arrival[:start])
        @log.info("Payment arrived to #{id} at ##{t.id} in #{Zold::Age.new(arrival[:start])}: #{t.details}")
        @waiting.delete(t.details)
      end
    end
    @stats.put('match_ok', Time.now - start)
  end

  private

  def blame(ex, start, label)
    @log.error(Backtrace.new(ex))
    @stats.put(label, Time.now - start)
  end

  def pull(id)
    start = Time.now
    Zold::Pull.new(wallets: @wallets, remotes: @remotes, copies: @copies, log: @log).run(
      ['pull', id.to_s, "--network=#{@network}", '--ignore-score-weakness']
    )
    @stats.put('pull_ok', Time.now - start)
  rescue StandardError => e
    blame(e, start, 'pull_errors')
  end

  def push(id)
    start = Time.now
    Zold::Push.new(wallets: @wallets, remotes: @remotes, log: @log).run(
      ['push', id.to_s, "--network=#{@network}", '--ignore-score-weakness']
    )
    @stats.put('push_ok', Time.now - start)
  rescue StandardError => e
    blame(e, start, 'push_errors')
  end
end
