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

require 'zold/http'
require_relative 'pgsql'
require_relative 'user_error'

# SMS messages.
# Author:: Yegor Bugayenko (yegor256@gmail.com)
# Copyright:: Copyright (c) 2018 Yegor Bugayenko
# License:: MIT
class WTS::Smss
  # Fake
  class Fake
    def send(_phone, _msg)
      # Nothing
    end
  end

  def initialize(pgsql, sns, log: Zold::Log::NULL)
    @pgsql = pgsql
    @sns = sns
    @log = log
  end

  # Send a new SMS
  def send(phone, msg)
    recent = @pgsql.exec(
      'SELECT COUNT(*) FROM sms WHERE phone = $1 AND created > NOW() - INTERVAL \'4 HOURS\'',
      [phone]
    )[0]['count'].to_i
    if recent > 16 && ENV['RACK_ENV'] != 'test'
      raise WTS::UserError, '183: We\'ve sent too many of them already, wait for a few hours and try again'
    end
    total = @pgsql.exec('SELECT COUNT(*) FROM sms WHERE created > NOW() - INTERVAL \'4 HOURS\'')[0]['count'].to_i
    if total > 256 && ENV['RACK_ENV'] != 'test'
      raise WTS::UserError, '180: We\'ve sent too many of them already, we have to relax for a while'
    end
    rid = 999
    rid = @sns.publish(phone_number: "+#{phone}", message: msg)[:message_id] if ENV['RACK_ENV'] != 'test'
    cid = @pgsql.exec(
      [
        'INSERT INTO sms (phone, message_id)',
        'VALUES ($1, $2)',
        'RETURNING id'
      ].join(' '),
      [phone, rid]
    )[0]['id'].to_i
    @log.info("New SMS ##{cid}/#{rid} sent to +#{phone}: #{msg}")
    cid
  end
end
