# frozen_string_literal: true

# SPDX-FileCopyrightText: Copyright (c) 2018-2026 Zerocracy
# SPDX-License-Identifier: MIT

require 'backtrace'
require 'loog'
require 'upwork/api'
require 'upwork/api/routers/payments'
require_relative 'user_error'
require_relative 'wts'

class WTS::Upwork
  def initialize(config, team, log: Loog::NULL)
    @config = config
    @team = team
    @log = log
  end

  def pay(contract, usd, details)
    client = Upwork::Api::Client.new(Upwork::Api::Config.new(@config))
    begin
      res = Upwork::Api::Routers::Payments.new(client).submit_bonus(
        @team,
        'engagement__reference' => contract,
        'comments' => details,
        'charge_amount' => usd
      )
      raise(res['error']['message']) if res['error']
      res['reference']
    rescue StandardError => e
      @log.error(Backtrace.new(e))
      raise(
        RuntimeError,
        "Failed to send $#{usd} to UpWork #{contract} with details of #{details.inspect}: #{e.message}"
      )
    end
  end
end
