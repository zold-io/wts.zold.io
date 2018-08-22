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

require 'zold/key'
require 'zold/id'
require 'zold/commands/create'
require 'zold/commands/pull'
require 'zold/commands/push'
require 'zold/commands/pay'
require 'zold/commands/remove'

#
# The stress tester.
#
class Stress
  # Number of wallets to work with
  POOL_SIZE = 64

  # Amount to send in each payment
  AMOUNT = Zold::Amount.new(zld: 0.01)

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

  end

  def to_json
    {
      'wallets': @wallets.all.count
    }
  end

  def start
    Thread.new do
      wallets.all.count
    end
  end

  def pay
    raise 'Too few wallets in the pool' if @wallets.all.count < 2
    first = @wallets.all.shuffle[0]
    second = @wallets.all.shuffle[0] while second == first
    Zold::Pay.new(wallets: @wallets, remotes: @remotes, copies: @copies, log: @log).run(
      ['pay', first, second, Stress::AMOUNT.to_zld(, '', '--network=zold']
    )
    push(Zold::Id.new(first))
  end

  def reload
    Zold::Pull.new(wallets: @wallets, remotes: @remotes, copies: @copies, log: @log).run(
      ['pull', @id.to_s, '--network=zold']
    )
    loop do
      pulled = 0
      @wallets.all.shuffle.each do |id|
        @wallets.find(Zold::Id.new(id)) do |w|
          w.txns.each do |t|
            next unless t.amount.negative?
            next if @wallets.all.include?(t.bnf.to_s)
            next if @wallets.all.count > Stress::POOL_SIZE
            pulled += pull(t.bnf)
          end
        end
      end
      break if pulled.zero?
    end
    @wallets.all.each do |id|
      next if @wallets.find(Zold::Id.new(id), &:balance) > Stress::AMOUNT * 4
      Zold::Remove.new(wallets: @wallets, log: @log).run(
        ['remove', '--network=zold']
      )
    end
    while @wallets.all.count < Stress::POOL_SIZE
      Zold::Create.new(wallets: @wallets, log: @log).run(
        ['create', '--network=zold']
      )
    end
    while @wallets.all.count > Stress::POOL_SIZE
      Zold::Remove.new(wallets: @wallets, log: @log).run(
        ['remove', @wallets.all.shuffle[0].to_s]
      )
    end
    @log.info("There are #{@wallets.all.count} wallets in the pool")
  end

  private

  def pull(id)
    Zold::Pull.new(wallets: @wallets, remotes: @remotes, copies: @copies, log: @log).run(
      ['pull', id.to_s, '--network=zold']
    )
    1
  rescue StandardError => e
    @log.error(e.message)
    0
  end

  def push(id)
    Zold::Push.new(wallets: @wallets, remotes: @remotes, copies: @copies, log: @log).run(
      ['push', id.to_s, '--network=zold']
    )
    1
  rescue StandardError => e
    @log.error(e.message)
    0
  end
end
