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
  def initialize(login, item, wallets, log: Zold::Log::Quiet.new)
    raise 'Login can\'t be nil' if login.nil?
    @login = login.downcase
    raise 'Item can\'t be nil' if item.nil?
    @item = item
    raise 'Wallets can\'t be nil' if wallets.nil?
    @wallets = wallets
    raise 'Log can\'t be nil' if log.nil?
    @log = log
  end

  # Create it, if it's absent (returns TRUE if it was created just now)
  def create
    return false if @item.exists?
    rsa = OpenSSL::PKey::RSA.new(2048)
    pvt = Zold::Key.new(text: rsa.to_pem)
    wallet = Tempfile.open do |f|
      File.write(f, rsa.public_key.to_pem)
      require 'zold/commands/create'
      Zold::Create.new(wallets: @wallets, log: @log).run(
        ['create', '--public-key=' + f.path]
      )
    end
    @item.create(wallet.id, pvt)
    true
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
end
