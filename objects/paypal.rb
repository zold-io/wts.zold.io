# Copyright (c) 2018-2019 Zerocracy, Inc.
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
require 'paypal-sdk-rest'
require_relative 'user_error'

#
# PayPal sending out gateway.
#
class PayPalGate
  def initialize(id, secret, log: Zold::Log::NULL)
    @id = id
    @secret = secret
    @log = log
  end

  # Send PayPal
  def send(email, usd, details)
    # PayPal::SDK::REST.set_config(
    #   :mode => 'live',
    #   :client_id => @id,
    #   :client_secret => @secret
    # )
    # see https://github.com/paypal/PayPal-Ruby-SDK/issues/377
  rescue StandardError => e
    @log.error(Backtrace.new(e))
    raise "Failed to send $#{usd} to #{email.inspect} with details of #{details.inspect}: #{e.message}"
  end
end
