# Copyright (c) 2018-2025 Zerocracy
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

require 'backtrace'
require 'zold/log'
require 'coinbase/wallet'
require_relative 'wts'
require_relative 'user_error'

#
# Coinbase gateway.
#
class WTS::Coinbase
  # If payment can't be sent right now, but may work later in the future.
  class TryLater < StandardError; end

  # Fake one
  class Fake
    def balance
      1
    end

    def buy(_usd)
      # Nothing
    end

    def pay(_address, _usd, _details)
      # Nothing
    end
  end

  def initialize(key, secret, account, log: Zold::Log::NULL)
    @key = key
    @secret = secret
    @account = account
    @log = log
  end

  # Get BTC balance, in BTC
  def balance
    acc = Coinbase::Wallet::Client.new(api_key: @key, api_secret: @secret).account(@account)
    acc.balance['amount'].to_f
  end

  # Convert USD to BTC.
  def buy(usd)
    acc = Coinbase::Wallet::Client.new(api_key: @key, api_secret: @secret).account(@account)
    response = acc.buy(amount: usd.to_s, currency: 'USD')
    response['id']
  end

  # Send BTC.
  def pay(address, btc, details)
    acc = Coinbase::Wallet::Client.new(api_key: @key, api_secret: @secret).account(@account)
    response = acc.send(to: address, amount: btc, currency: 'BTC', description: details)
    @log.info("Coinbase payment has been sent, their transaction ID is #{response['id']}")
    response['id']
  rescue Coinbase::Wallet::ValidationError => e
    raise TryLater, e.message
  rescue StandardError => e
    @log.error(Backtrace.new(e))
    raise "Failed to send \"#{btc}\" to \"#{address}\" with details of \"#{details}\": #{e.message}"
  end
end
