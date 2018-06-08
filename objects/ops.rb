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

require 'tempfile'
require 'openssl'
require 'zold/log'

#
# Operations with a user.
#
class Ops
  def initialize(item, user, wallets, remotes, copies, log: Zold::Log::Quiet.new)
    raise 'User can\'t be nil' if user.nil?
    @user = user
    raise 'Item can\'t be nil' if item.nil?
    @item = item
    raise 'Wallets can\'t be nil' if wallets.nil?
    @wallets = wallets
    raise 'Remotes can\'t be nil' if remotes.nil?
    @remotes = remotes
    raise 'Copies can\'t be nil' if copies.nil?
    @copies = copies
    raise 'Log can\'t be nil' if log.nil?
    @log = log
  end

  def pull
    require 'zold/commands/remote'
    Zold::Remote.new(remotes: @remotes, log: @log).run(['update'])
    Zold::Remote.new(remotes: @remotes, log: @log).run(['trim'])
    id = @item.id
    require 'zold/commands/pull'
    Zold::Pull.new(wallets: @wallets, remotes: @remotes, copies: @copies, log: @log).run(
      ['pull', id.to_s]
    )
    wallet = @wallets.find(id)
    @log.info("#{Time.now.utc.iso8601}: Wallet #{wallet.id} pulled successfully, the balance is #{wallet.balance}\n")
  end

  def push
    wallet = @user.wallet
    require 'zold/commands/push'
    Zold::Push.new(wallets: @wallets, remotes: @remotes, log: @log).run(
      ['pull', wallet.id.to_s]
    )
    @log.info("#{Time.now.utc.iso8601}: Wallet #{wallet.id} pushed successfully, the balance is #{wallet.balance}\n")
  end

  def pay(pass, bnf, amount, details)
    raise 'Pass can\'t be nil' if pass.nil?
    raise 'Beneficiary can\'t be nil' if bnf.nil?
    raise 'Beneficiary must be of type Id' unless bnf.is_a?(Zold::Id)
    raise 'Amount can\'t be nil' if amount.nil?
    raise 'Payment amount can\'t be zero' if amount.zero?
    raise 'Payment amount can\'t be negative' if amount.negative?
    raise 'Amount must be of type Amount' unless amount.is_a?(Zold::Amount)
    raise 'Details can\'t be nil' if details.nil?
    raise 'The account is not confirmed yet' unless @user.confirmed?
    w = @user.wallet
    Tempfile.open do |f|
      File.write(f, @item.key(pass))
      require 'zold/commands/pay'
      Zold::Pay.new(wallets: @wallets, remotes: @remotes, log: @log).run(
        ['pay', '--private-key=' + f.path, w.id.to_s, bnf.to_s, amount.to_zld(8), details, '--force']
      )
    end
    require 'zold/commands/push'
    Zold::Push.new(wallets: @wallets, remotes: @remotes, log: @log).run(
      ['push', w.id.to_s, bnf.to_s]
    )
    @log.info("#{Time.now.utc.iso8601}: Paid #{amount} from #{w.id} to #{bnf}: #{details}\n")
  end
end
