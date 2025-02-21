# SPDX-FileCopyrightText: Copyright (c) 2018-2025 Zerocracy
# SPDX-License-Identifier: MIT

require 'zold/http'
require_relative 'user_error'

# SMS messages.
# Author:: Yegor Bugayenko (yegor256@gmail.com)
# Copyright:: Copyright (c) 2018 Yegor Bugayenko
# License:: MIT
class WTS::Smss
  # Fake
  class Fake
    def deliver(_phone, _msg)
      # Nothing
    end
  end

  def initialize(pgsql, sns, log: Zold::Log::NULL)
    @pgsql = pgsql
    @sns = sns
    @log = log
  end

  # Send a new SMS
  def deliver(phone, msg)
    recent = @pgsql.exec(
      'SELECT COUNT(*) FROM sms WHERE phone = $1 AND created > NOW() - INTERVAL \'4 HOURS\'',
      [phone]
    )[0]['count'].to_i
    if recent > 16 && ENV['RACK_ENV'] != 'test'
      raise WTS::UserError, 'E183: We\'ve sent too many of them already, wait for a few hours and try again'
    end
    total = @pgsql.exec('SELECT COUNT(*) FROM sms WHERE created > NOW() - INTERVAL \'4 HOURS\'')[0]['count'].to_i
    if total > 256 && ENV['RACK_ENV'] != 'test'
      raise WTS::UserError, 'E180: We\'ve sent too many of them already, we have to relax for a while'
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
