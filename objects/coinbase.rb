# frozen_string_literal: true

# SPDX-FileCopyrightText: Copyright (c) 2018-2026 Zerocracy
# SPDX-License-Identifier: MIT

require 'backtrace'
require 'coinbase/wallet'
require 'loog'
require_relative 'user_error'
require_relative 'wts'

class WTS::Coinbase
  class WTS::Coinbase::TryLater < StandardError; end

  class WTS::Coinbase::Fake
    def balance
      1
    end

    def buy(_usd); end

    def pay(_address, _usd, _details); end
  end

  def initialize(key, secret, account, log: Loog::NULL)
    @key = key
    @secret = secret
    @account = account
    @log = log
  end

  def balance
    Coinbase::Wallet::Client.new(api_key: @key, api_secret: @secret).account(@account).balance['amount'].to_f
  end

  def buy(usd)
    Coinbase::Wallet::Client.new(api_key: @key, api_secret: @secret).account(@account).buy(
      amount: usd.to_s,
      currency: 'USD'
    )['id']
  end

  def pay(address, btc, details)
    response = Coinbase::Wallet::Client.new(api_key: @key, api_secret: @secret).account(@account).send( # rubocop:disable Style/Send
      to: address,
      amount: btc, currency: 'BTC', description: details
    )
    @log.info("Coinbase payment has been sent, their transaction ID is #{response['id']}")
    response['id']
  rescue Coinbase::Wallet::ValidationError => e
    raise(TryLater, e.message)
  rescue StandardError => e
    @log.error(Backtrace.new(e))
    raise(RuntimeError, "Failed to send \"#{btc}\" to \"#{address}\" with details of \"#{details}\": #{e.message}")
  end
end
