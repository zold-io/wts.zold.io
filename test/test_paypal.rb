# frozen_string_literal: true

# SPDX-FileCopyrightText: Copyright (c) 2018-2026 Zerocracy
# SPDX-License-Identifier: MIT

require_relative '../objects/paypal'
require_relative '../objects/wts'
require_relative 'test__helper'

class WTS::PayPalTest < Minitest::Test
  def test_sends_paypal
    skip
    WebMock.allow_net_connect!
    assert(
      WTS::PayPal.new(
        {
          id: 'Aayp...',
          secret: 'EDP...',
          email: 'pp@zerocracy.com',
          login: '...',
          password: '...',
          signature: '...',
          appid: 'APP-...'
        },
        log: t_log
      ).pay('yegor256@gmail.com', 1.28, 'Just a test').start_with?('AP-')
    )
  end

  def test_makes_sender_pay_paypal_fees
    seen = {}
    fake = Object.new
    fake.define_singleton_method(:setup_purchase) do |opts|
      seen.merge!(opts)
      { 'responseEnvelope' => { 'ack' => 'Success' }, 'payKey' => 'AP-8XK2' }
    end
    gateway = ActiveMerchant::Billing::PaypalAdaptivePayment.singleton_class
    gateway.alias_method(:original_new, :new)
    gateway.define_method(:new) { |*| fake }
    begin
      WTS::PayPal.new(
        { email: 'xq@zerocracy.com', login: 'ql', password: 'pw7', signature: 'sg3', appid: 'APP-91' },
        log: t_log
      ).pay('rt@example.org', 3.71, 'Fees test')
    ensure
      gateway.alias_method(:new, :original_new)
      gateway.remove_method(:original_new)
    end
    assert_equal('SENDER', seen[:fees_payer], 'PayPal fees are not paid by the sender')
  end
end
