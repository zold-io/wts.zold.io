# frozen_string_literal: true

# SPDX-FileCopyrightText: Copyright (c) 2018-2026 Zerocracy
# SPDX-License-Identifier: MIT

require 'zold/amount'
require_relative '../objects/bonuses'
require_relative 'test__helper'

class WTS::BonusesTest < Minitest::Test
  class Boss
    attr_accessor :balance

    def initialize(balance)
      @balance = balance
    end

    def wallet
      yield(Struct.new(:balance).new(@balance))
    end
  end

  class Cashier
    attr_reader :paid

    def initialize(boss, left)
      @boss = boss
      @left = left
      @paid = []
    end

    def pay_taxes(_keygap)
      @boss.balance = Zold::Amount.new(zld: @left)
    end

    def pull; end

    def push; end

    def pay(_keygap, invoice, _amount, _details)
      @paid << invoice
    end
  end

  def test_stops_paying_when_taxes_ate_the_balance
    boss = Boss.new(Zold::Amount.new(zld: 1.01))
    cashier = Cashier.new(boss, 0.02)
    WTS::Bonuses.new(boss, cashier, 'keygap').pay(
      [Struct.new(:invoice, :host, :port, :value).new('a@b', 'h', 80, 5)],
      Zold::Amount.new(zld: 0.12)
    )
    assert_empty(cashier.paid, 'The bonus was paid from a wallet that cannot afford it')
  end

  def test_pays_when_the_balance_is_enough
    boss = Boss.new(Zold::Amount.new(zld: 1.01))
    cashier = Cashier.new(boss, 1.0)
    WTS::Bonuses.new(boss, cashier, 'keygap').pay(
      [Struct.new(:invoice, :host, :port, :value).new('a@b', 'h', 80, 5)],
      Zold::Amount.new(zld: 0.12)
    )
    assert_equal(['a@b'], cashier.paid, 'The bonus was not paid')
  end
end
