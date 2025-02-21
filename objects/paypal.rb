# SPDX-FileCopyrightText: Copyright (c) 2018-2025 Zerocracy
# SPDX-License-Identifier: MIT

require 'backtrace'
require 'zold/log'
require 'paypal-sdk-rest'
require 'active_paypal_adaptive_payment'
require_relative 'wts'
require_relative 'user_error'

#
# PayPal sending out gateway.
#
class WTS::PayPal
  def initialize(config, log: Zold::Log::NULL)
    @config = config
    @log = log
  end

  # Send PayPal
  def pay(email, usd, details)
    require 'openssl'
    OpenSSL::SSL.const_set(:VERIFY_PEER, OpenSSL::SSL::VERIFY_NONE)
    gateway = ActiveMerchant::Billing::PaypalAdaptivePayment.new(
      mode: 'live',
      login: @config[:login],
      password: @config[:password],
      signature: @config[:signature],
      appid: @config[:appid]
    )
    response = gateway.setup_purchase(
      action_type: 'PAY',
      sender_email: @config[:email],
      return_url: 'https://wts.zold.io/terms',
      cancel_url: 'https://wts.zold.io/terms',
      memo: details,
      receiver_list: [
        {
          email: email,
          amount: usd
        }
      ]
    )
    unless response['responseEnvelope']['ack'] == 'Success'
      raise "Failed to send $#{usd} to #{email.inspect} with details of #{details.inspect}: #{response.json}"
    end
    key = response['payKey']
    @log.info("Sent #{usd} to #{email} via PayPal: #{key}")
    key
  end

  private

  # Send via PayPal Payouts API. This mechanism is not convenient at all,
  # since it requires us to keep enough money on PayPal account, to have
  # an ability to send payments. Check this SO thread, to see what I mean:
  # https://stackoverflow.com/questions/31485919/paypal-single-payout-sender-insufficient-funds-error
  #
  # We keep this method in the class just in case. Maybe PayPal changes
  # something in the future and we will get back to this Payouts API.
  def send_payouts_api(email, usd, details)
    PayPal::SDK.configure(
      mode: 'live',
      client_id: @config[:id],
      client_secret: @config[:secret],
      ssl_options: {}
    )
    payout = PayPal::SDK::REST::Payout.new(
      sender_batch_header: {
        sender_batch_id: SecureRandom.hex(8),
        email_subject: details
      },
      items: [
        {
          recipient_type: 'EMAIL',
          amount: { value: usd.to_s, currency: 'USD' },
          note: details,
          receiver: email,
          sender_item_id: SecureRandom.hex(8)
        }
      ]
    )
    begin
      batch = payout.create
      @log.info("Created PayPal payout ##{batch.batch_header.payout_batch_id}")
      batch.batch_header.payout_batch_id
    rescue PayPal::SDK::REST::ResourceNotFound => e
      raise "Failed to send $#{usd} to #{email.inspect}: #{payout.error.inspect} #{e.message}"
    rescue StandardError => e
      @log.error(Backtrace.new(e))
      raise "Failed to send $#{usd} to #{email.inspect} with details of #{details.inspect}: #{e.message}"
    end
  end
end
