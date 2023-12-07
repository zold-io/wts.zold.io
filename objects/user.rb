# Copyright (c) 2018-2023 Zerocracy
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
require 'zold/id'
require_relative 'wts'
require_relative 'user_error'

#
# The user.
#
class WTS::User
  attr_reader :item, :login

  def initialize(login, item, wallets, log: Zold::Log::NULL)
    @login = login.downcase
    @item = item
    @wallets = wallets
    @log = log
  end

  # It is a testing user, who is not allowed to do any real operations?
  def fake?
    @login == Zold::Id::ROOT.to_s
  end

  # Is it a mobile user?
  def mobile?
    /^[0-9]+$/.match?(@login)
  end

  # Create user's wallet, if it's absent (returns TRUE if it was created just now)
  def create(remotes = Zold::Remotes::Empty.new)
    rsa = OpenSSL::PKey::RSA.new(2048)
    pvt = Zold::Key.new(text: rsa.to_pem)
    wallet = Tempfile.open do |f|
      File.write(f, rsa.public_key.to_pem)
      require 'zold/commands/create'
      Zold::Create.new(wallets: @wallets, remotes: remotes, log: @log).run(
        ['create', '--public-key=' + f.path]
      )
    end
    @item.create(wallet, pvt)
    @log.info("Wallet #{wallet} created successfully\n")
    true
  end

  def invoice
    require 'zold/commands/invoice'
    Zold::Invoice.new(wallets: @wallets, remotes: @remotes, copies: @copies, log: @log).run(
      ['invoice', wallet(&:id).to_s]
    )
  end

  # The user has already confirmed that he saved the keygap
  # code in a safe place.
  def confirmed?
    @item.wiped?
  end

  # The user confirms that the keygap is stored.
  def confirm(keygap)
    raise 'Keygap can\'t be nil' if keygap.nil?
    @item.wipe(keygap)
  end

  # Get user keygap, if it's still available in the database. Otherwise,
  # raise an exception.
  def keygap
    raise 'The user has already confirmed the keygap, we don\'t keep it anymore' if confirmed?
    @item.keygap
  end

  def wallet_exists?
    @item.exists? && @wallets.acq(@item.id, &:exists?)
  end

  def wallet
    id = @item.id
    @wallets.acq(id) do |wallet|
      raise WTS::UserError, "E100: You have to pull the wallet #{id} first (#{@login})" unless wallet.exists?
      @item.touch
      yield wallet
    end
  end
end
