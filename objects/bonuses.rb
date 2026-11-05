# frozen_string_literal: true

# SPDX-FileCopyrightText: Copyright (c) 2018-2026 Zerocracy
# SPDX-License-Identifier: MIT

require_relative 'user_error'

class WTS::Bonuses
  def initialize(boss, ops, keygap)
    @boss = boss
    @ops = ops
    @keygap = keygap
  end

  def pay(winners, share)
    winners.each do |score|
      @ops.pull
      @ops.pay_taxes(@keygap)
      @ops.push
      break if @boss.wallet(&:balance) < share
      @ops.pay(@keygap, score.invoice, share, "Hosting bonus for #{score.host} #{score.port} #{score.value}")
      @ops.push
    end
  end
end
