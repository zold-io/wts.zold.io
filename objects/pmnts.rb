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
require 'zold/tax'
require 'zold/commands/pay'
require 'zold/commands/remote'
require 'zold/commands/taxes'
require_relative 'stats'

#
# Payments to be sent.
#
class Pmnts
  def initialize(pvt:, wallets:, remotes:, stats:, log: Zold::Log::Quiet.new)
    raise 'Private RSA key can\'t be nil' if pvt.nil?
    raise 'Private RSA key must be of type Key' unless pvt.is_a?(Zold::Key)
    @pvt = pvt
    raise 'Wallets can\'t be nil' if wallets.nil?
    @wallets = wallets
    @remotes = remotes
    raise 'Log can\'t be nil' if log.nil?
    @log = log
    @stats = stats
  end

  def send
    raise 'Too few wallets in the pool' if @wallets.all.count < 2
    paid = []
    Tempfile.open do |f|
      File.write(f, @pvt.to_s)
      @wallets.all.each do |source|
        balance = @wallets.find(source, &:balance)
        next if balance.negative? || balance.zero?
        amount = balance / @wallets.all.count
        next if amount < Zold::Amount.new(zld: 0.0001)
        @wallets.all.each do |target|
          next if source == target
          paid << pay_one(source, target, amount, f.path)
        end
      end
    end
    paid
  end

  private

  def pay_one(source, target, amount, pvt)
    Zold::Taxes.new(wallets: @wallets, remotes: @remotes, log: @log).run(
      ['taxes', 'pay', source.to_s, "--network=#{@network}", "--private-key=#{pvt}", '--ignore-nodes-absence']
    )
    if @wallets.find(source) { |w| Zold::Tax.new(w).in_debt? }
      @log.error("The wallet #{source} is still in debt and we can't pay taxes")
      return
    end
    details = SecureRandom.uuid
    @stats.exec('paid', swallow: false) do
      Zold::Pay.new(wallets: @wallets, remotes: @remotes, log: @log).run(
        ['pay', source.to_s, target.to_s, amount.to_zld(4), details, "--network=#{@network}", "--private-key=#{pvt}"]
      )
    end
    { start: Time.now, source: source, target: target, details: details }
  end
end
