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
# The user.
#
class User
  def initialize(login, item, wallets, remotes, copies, log: Zold::Log::Quiet.new)
    raise 'Login can\'t be nil' if login.nil?
    @login = login.downcase
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

  # Create it, if it's absent
  def create
    return if @item.exists?
    rsa = OpenSSL::PKey::RSA.new(2048)
    pvt = Zold::Key.new(text: rsa.to_pem)
    wallet = Tempfile.open do |f|
      File.write(f, rsa.public_key.to_pem)
      require 'zold/commands/create'
      wallet = Zold::Create.new(wallets: @wallets, log: @log).run(
        ['create', '--public-key=' + f.path]
      )
      require 'zold/commands/push'
      Zold::Push.new(wallets: @wallets, remotes: @remotes, log: @log).run(
        ['push', wallet.id.to_s]
      )
      wallet
    end
    @item.create(wallet.id, pvt)
    # Here we should pay the sign-up bonus
  end

  # The user has already confirmed that he saved the pass
  # code in a safe place.
  def confirmed?
    @item.wiped?
  end

  # The user confirms that the pass code is stored.
  def confirm(pass)
    raise 'Pass can\'t be nil' if pass.nil?
    @item.wipe(pass)
  end

  # Get user pass, if it's still available in the database. Otherwise,
  # raise an exception.
  def pass
    raise 'The user has already confirmed the pass, we don\'t keep it anymore' if confirmed?
    @item.pass
  end

  # Return user's Wallet (as Zold::Wallet)
  def wallet
    @wallets.find(@item.id)
  end

  def pull
    require 'zold/commands/pull'
    Zold::Pull.new(wallets: @wallets, remotes: @remotes, copies: @copies, log: @log).run(
      ['pull', wallet.id.to_s]
    )
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
    raise 'The account is not confirmed yet' unless confirmed?
    Tempfile.open do |f|
      File.write(f, @item.key(pass))
      w = wallet
      require 'zold/commands/pay'
      Zold::Pay.new(wallets: @wallets, remotes: @remotes, log: @log).run(
        ['pay', '--private-key=' + f.path, w.id.to_s, bnf.to_s, amount.to_zld(8), details, '--force']
      )
      require 'zold/commands/push'
      Zold::Push.new(wallets: @wallets, remotes: @remotes, log: @log).run(
        ['push', w.id.to_s, bnf.to_s]
      )
    end
  end
end
