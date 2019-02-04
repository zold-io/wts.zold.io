# Copyright (c) 2018-2019 Zerocracy, Inc.
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
require_relative 'user_error'

#
# Operations with a user.
#
class Ops
  def initialize(item, user, wallets, remotes, copies, log: Zold::Log::NULL, network: 'test')
    @user = user
    @item = item
    @wallets = wallets
    @remotes = remotes
    @copies = copies
    @log = log
    @network = network
  end

  def pull
    start = Time.now
    id = @item.id
    raise UserError, "There are no visible remote nodes, can\'t PULL #{id}" if @remotes.all.empty?
    require 'zold/commands/pull'
    begin
      Zold::Pull.new(wallets: @wallets, remotes: @remotes, copies: @copies, log: @log).run(
        ['pull', id.to_s, "--network=#{@network}", '--retry=4']
      )
    rescue Zold::Fetch::EdgesOnly, Zold::Fetch::NoQuorum => e
      raise UserError, e.message
    end
    @log.info("#{Time.now.utc.iso8601}: Wallet #{id} pulled successfully \
in #{(Time.now - start).round}s\n \n ")
  end

  def push
    start = Time.now
    id = @item.id
    raise UserError, "There are no visible remote nodes, can\'t PUSH #{id}" if @remotes.all.empty?
    require 'zold/commands/push'
    begin
      Zold::Push.new(wallets: @wallets, remotes: @remotes, log: @log).run(
        ['push', id.to_s, "--network=#{@network}", '--retry=4']
      )
    rescue Zold::Push::EdgesOnly, Zold::Push::NoQuorum => e
      raise UserError, e.message
    end
    @log.info("#{Time.now.utc.iso8601}: Wallet #{id} pushed successfully \
in #{(Time.now - start).round}s\n \n ")
  end

  def pay(keygap, bnf, amount, details)
    raise UserError, 'Payment amount can\'t be zero' if amount.zero?
    raise UserError, 'Payment amount can\'t be negative' if amount.negative?
    raise "The user @#{@user.login} is not registered yet" unless @item.exists?
    raise "The account @#{@user.login} is not confirmed yet" unless @user.confirmed?
    start = Time.now
    id = @item.id
    pull
    raise 'There is no wallet file after PULL, can\'t pay' unless @wallets.acq(id, &:exists?)
    Tempfile.open do |f|
      File.write(f, @item.key(keygap))
      require 'zold/commands/pay'
      Zold::Pay.new(wallets: @wallets, remotes: @remotes, copies: @copies, log: @log).run(
        ['pay', '--private-key=' + f.path, id.to_s, bnf.to_s, amount.to_zld(8), details]
      )
    end
    push
    @log.info("#{Time.now.utc.iso8601}: Paid #{amount} from #{id} to #{bnf} \
in #{(Time.now - start).round}s: #{details}\n \n ")
  end
end
