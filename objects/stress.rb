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
        @wallets.find(Zold::Id.new(id)) do |w|
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
            reload
            @log.info("Reloaded, #{@wallets.all.count} wallets in the pool")
            pay
            refetch
            @log.info("#{@wallets.all.count} wallets remained after re-fetch")
            match
            @stats.put('cycles_ok', Time.now - start)
          rescue StandardError => e
            blame(e, start, 'cycle_errors')
          end
          @log.info("Cycle no.#{cycle} finished in #{(Time.now - start).round(2)}s")
          sleep(delay)
          cycle += 1
          break if cycles.positive? && cycle >= cycles
        end
        @log.info("Stress thread finished after cycle no.#{cycle}")
      end
    end
  end

  def update
    cmd = Zold::Remote.new(remotes: @remotes, log: @log)
    args = ['remote', "--network=#{@network}"]
    cmd.run(args + ['trim'])
    cmd.run(args + ['reset']) if @remotes.all.empty?
    cmd.run(args + ['update'])
    cmd.run(args + ['select'])
  end

  def reload
    start = Time.now
    pull(@id)
    loop do
      pulled = 0
      @wallets.all.shuffle.each do |id|
        @wallets.find(Zold::Id.new(id), &:txns).each do |t|
          next unless t.amount.negative?
          next if @wallets.all.include?(t.bnf.to_s)
          next if @wallets.all.count > Stress::POOL_SIZE
          pull(t.bnf)
          pulled += 1
        end
      end
      break if pulled.zero?
    end
    @wallets.all.each do |id|
      next if @wallets.find(Zold::Id.new(id), &:balance) > Stress::AMOUNT
      next if @waiting.values.find { |w| w[:id] == id }
      Zold::Remove.new(wallets: @wallets, log: @log).run(
        ['remove', id.to_s]
      )
    end
    Tempfile.open do |f|
      File.write(f, @pub.to_s)
      while @wallets.all.count < Stress::POOL_SIZE
        Zold::Create.new(wallets: @wallets, log: @log).run(
          ['create', "--network=#{@network}", "--public-key=#{f.path}"]
        )
      end
    end
    # while @wallets.all.count > Stress::POOL_SIZE
    #   Zold::Remove.new(wallets: @wallets, log: @log).run(
    #     ['remove', @wallets.all.sample.to_s]
    #   )
    # end
    @stats.put('reload_ok', Time.now - start)
  end

  def pay
    raise 'Too few wallets in the pool' if @wallets.all.count < 2
    start = Time.now
    seen = []
    paid = []
    loop do
      raise "No suitable wallets amoung #{seen.count} in the pool" if seen.count == @wallets.all.count
      first = @wallets.all.sample(1)[0]
      next if seen.include?(first)
      seen << first
      next if @wallets.find(Zold::Id.new(first), &:balance) < Stress::AMOUNT
      Tempfile.open do |f|
        File.write(f, @pvt.to_s)
        @wallets.all.each do |id|
          next if id == first
          break if @wallets.find(Zold::Id.new(first), &:balance) < Stress::AMOUNT
          pay_one(first, id, f.path)
          paid << id
        end
      end
      paid << first
      break
    end
    paid.uniq.peach(Concurrent.processor_count * 8) do |id|
      push(Zold::Id.new(id))
    end
    @stats.put('pay_ok', Time.now - start)
  end

  def pay_one(source, target, pvt)
    Zold::Taxes.new(wallets: @wallets, remotes: @remotes, log: @log).run(
      ['taxes', 'pay', source, "--network=#{@network}", "--private-key=#{pvt}", '--ignore-nodes-absence']
    )
    if @wallets.find(Zold::Id.new(source)) { |w| Zold::Tax.new(w).in_debt? }
      @log.error("The wallet #{source} is still in debt (#{Zold::Tax.new(w).debt}) and we can't pay taxes")
      return
    end
    details = SecureRandom.uuid
    amount = Stress::AMOUNT
    Zold::Pay.new(wallets: @wallets, remotes: @remotes, log: @log).run(
      ['pay', source, target, amount.to_zld, details, "--network=#{@network}", "--private-key=#{pvt}"]
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
      pull(Zold::Id.new(id))
    end
    @stats.put('refetch_ok', Time.now - start)
  end

  def match
    start = Time.now
    @wallets.all.each do |id|
      @wallets.find(Zold::Id.new(id), &:txns).each do |t|
        next if t.amount.negative?
        next unless @waiting[t.details]
        @stats.put('arrived', Time.now - @waiting[t.details][:start])
        @waiting.delete(t.details)
        @log.info("Payment arrived to #{id} at ##{t.id}: #{t.details}")
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
