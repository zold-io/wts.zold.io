# SPDX-FileCopyrightText: Copyright (c) 2018-2025 Zerocracy
# SPDX-License-Identifier: MIT

require 'backtrace'
require 'zold/log'
require 'upwork/api'
require 'upwork/api/routers/payments'
require_relative 'wts'
require_relative 'user_error'

#
# UpWork sending out gateway.
#
class WTS::Upwork
  def initialize(config, team, log: Zold::Log::NULL)
    @config = config
    @team = team
    @log = log
  end

  # Send to one contract
  def pay(contract, usd, details)
    client = Upwork::Api::Client.new(Upwork::Api::Config.new(@config))
    begin
      res = Upwork::Api::Routers::Payments.new(client).submit_bonus(
        @team,
        'engagement__reference' => contract,
        'comments' => details,
        'charge_amount' => usd
      )
      raise res['error']['message'] if res['error']
      res['reference']
    rescue StandardError => e
      @log.error(Backtrace.new(e))
      raise "Failed to send $#{usd} to UpWork #{contract} with details of #{details.inspect}: #{e.message}"
    end
  end
end
