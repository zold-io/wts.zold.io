# Copyright (c) 2018-2023 Zold
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
