# Copyright (c) 2018-2022 Zold
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
require 'zold/age'
require 'zold/commands/pull'
require 'zold/commands/remove'
require 'zold/commands/push'
require 'zold/commands/pay'
require 'zold/commands/taxes'
require 'zold/commands/create'
require_relative 'wts'
require_relative 'user_error'

#
# Operations with a user.
#
class WTS::Ops
  def initialize(item, user, wallets, remotes, copies, log: Zold::Log::NULL, network: 'test')
    @user = user
    @item = item
    @wallets = wallets
    @remotes = remotes
    @copies = copies
    @log = log
    @network = network
  end

  def remove
    @log.info("Removing the local copy of #{@item.id}...")
    Zold::Remove.new(wallets: @wallets, log: @log).run(
      ['remove', @item.id.to_s, '--force']
    )
  end

  def pull(id = @item.id)
    if @user.fake?
      @log.info("It is a fake user with wallet ID #{id}, won't PULL from the network")
      remove
      rsa = OpenSSL::PKey::RSA.new(2048)
      pvt = Zold::Key.new(text: rsa.to_pem)
      Tempfile.open do |f|
        File.write(f, rsa.public_key.to_pem)
        Zold::Create.new(wallets: @wallets, remotes: @remotes, log: @log).run(
          ['create', id.to_s, '--public-key=' + f.path]
        )
        @wallets.acq(id) do |wallet|
          wallet.add(
            Zold::Txn.new(
              1, Time.now, Zold::Amount.new(zld: 19.95), 'NOPREFIX', Zold::Id.new,
              'To help a friend'
            )
          )
          wallet.sub(Zold::Amount.new(zld: 9.90), "NOPREFIX@#{Zold::Id.new}", pvt, 'For pizza')
          wallet.sub(Zold::Amount.new(zld: 10.05), "NOPREFIX@#{Zold::Id.new}", pvt, 'For another pizza')
        end
      end
      return
    end
    start = Time.now
    if @remotes.all.empty?
      return if ENV['RACK_ENV'] == 'test'
      raise WTS::UserError, "E185: There are no visible remote nodes, can\'t PULL #{id}"
    end
    begin
      @log.info("Pulling #{id} from the network...")
      Zold::Pull.new(wallets: @wallets, remotes: @remotes, copies: @copies, log: @log).run(
        ['pull', id.to_s, "--network=#{@network}", '--retry=4', '--shallow']
      )
    rescue Zold::Fetch::NotFound => e
      raise WTS::UserError, "E186: We didn't manage to find your wallet #{@user.item.id} \
in any of visible Zold nodes (#{@user.login}). \
You should try to PULL again. If it doesn't work, most likely your wallet #{id} is lost \
and can't be recovered. If you have its copy locally, you can push it to the \
network from the console app, using PUSH command. Otherwise, go for \
the RESTART option in the top menu and create a new wallet. We are sorry to \
see this happening! #{e.message}"
    rescue Zold::Fetch::EdgesOnly, Zold::Fetch::NoQuorum => e
      raise WTS::UserError, e.message
    end
    @log.info("Wallet #{id} pulled successfully in #{Zold::Age.new(start)}")
  end

  def push
    if @user.fake?
      @log.info('It is a fake user, won\'t PUSH to the network')
      return
    end
    start = Time.now
    id = @item.id
    if @remotes.all.empty?
      return if ENV['RACK_ENV'] == 'test'
      raise WTS::UserError, "E187: There are no visible remote nodes, can\'t PUSH #{id}"
    end
    unless @wallets.acq(id, &:exists?)
      raise WTS::UserError, "EThe wallet #{id} of #{@user.login} is absent, can't PUSH; \
most probably you just have to RESTART your wallet"
    end
    begin
      @log.info("Pushing #{id} to the network...")
      Zold::Push.new(wallets: @wallets, remotes: @remotes, log: @log).run(
        ['push', id.to_s, "--network=#{@network}", '--retry=4']
      )
    rescue Zold::Push::EdgesOnly, Zold::Push::NoQuorum => e
      raise WTS::UserError, e.message
    end
    @log.info("Wallet #{id} pushed successfully in #{Zold::Age.new(start)}")
  end

  # Pay all required taxes, no matter what is the amount.
  def pay_taxes(keygap)
    raise "The user #{@user.login} is not registered yet" unless @item.exists?
    raise "The account #{@user.login} is not confirmed yet" unless @user.confirmed?
    if @user.fake?
      @log.info('It is a fake user, won\'t pay taxes')
      return
    end
    start = Time.now
    id = @item.id
    unless @wallets.acq(id, &:exists?)
      return if ENV['RACK_ENV'] == 'test'
      raise 'There is no wallet file after PULL, can\'t pay taxes'
    end
    Tempfile.open do |f|
      File.write(f, @item.key(keygap))
      @log.info("Paying taxes for #{id}...")
      Zold::Taxes.new(wallets: @wallets, remotes: @remotes, log: @log).run(
        [
          'taxes',
          'pay',
          "--network=#{@network}",
          'ignore-score-weakness',
          '--private-key=' + f.path,
          id.to_s
        ]
      )
    end
    @log.info("Taxes paid for #{id} in #{Zold::Age.new(start)}")
  end

  def pay(keygap, bnf, amount, details)
    raise WTS::UserError, 'E187: Payment amount can\'t be zero' if amount.zero?
    raise WTS::UserError, 'E188: Payment amount can\'t be negative' if amount.negative?
    raise "The user #{@user.login} is not registered yet" unless @item.exists?
    raise "The account #{@user.login} is not confirmed yet" unless @user.confirmed?
    if @user.fake?
      @log.info('It is a fake user, won\'t send a real payment')
      return
    end
    start = Time.now
    id = @item.id
    unless @wallets.acq(id, &:exists?)
      return if ENV['RACK_ENV'] == 'test'
      raise 'There is no wallet file after PULL, can\'t pay'
    end
    txn = Tempfile.open do |f|
      File.write(f, @item.key(keygap))
      @log.info("Paying #{amount} from #{id} to #{bnf}...")
      Zold::Pay.new(wallets: @wallets, remotes: @remotes, copies: @copies, log: @log).run(
        ['pay', "--network=#{@network}", '--private-key=' + f.path, id.to_s, bnf.to_s, "#{amount.to_i}z", details]
      )
    end
    @log.info("Paid #{amount} from #{id} to #{bnf} in #{Zold::Age.new(start)} #{details.inspect}: #{txn.to_text}")
    txn
  end

  def migrate(keygap)
    if @user.fake?
      @log.info('It is a fake user, won\'t migrate')
      return
    end
    start = Time.now
    pull
    pay_taxes(keygap)
    origin = @user.item.id
    balance = @user.wallet(&:balance)
    raise WTS::UserError, 'E206: The wallet is empty, nothing to migrate' if balance.zero?
    target = Tempfile.open do |f|
      File.write(f, @user.wallet(&:key).to_s)
      Zold::Create.new(wallets: @wallets, remotes: @remotes, log: @log).run(
        ['create', '--public-key=' + f.path]
      )
    end
    pay(keygap, target, balance, 'Migrated')
    push
    @user.item.replace_id(target)
    push
    @log.info("Wallet of #{@user.login} migrated from #{origin} to #{target} \
with #{balance}, in #{Zold::Age.new(start)}")
  end
end
