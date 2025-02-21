# SPDX-FileCopyrightText: Copyright (c) 2018-2025 Zerocracy
# SPDX-License-Identifier: MIT

require 'zold/log'
require_relative 'user_error'

#
# Mobile codes.
#
class WTS::Mcodes
  def initialize(pgsql, log: Zold::Log::NULL)
    @pgsql = pgsql
    @log = log
  end

  def exists?(phone)
    !@pgsql.exec('SELECT code FROM mcode WHERE phone = $1', [phone]).empty?
  end

  def set(phone, code)
    raise "Code must be over 1000: #{code}" if code < 1000
    raise "Code must be less than 10000: #{code}" if code > 9999
    @pgsql.exec('INSERT INTO mcode (phone, code) VALUES ($1, $2)', [phone, code])
  end

  def get(phone)
    r = @pgsql.exec('SELECT code FROM mcode WHERE phone = $1', [phone])[0]
    raise WTS::UserError, "EThere is not the code associated with #{phone}" if r.nil?
    r['code'].to_i
  end

  def remove(phone)
    @pgsql.exec('DELETE FROM mcode WHERE phone = $1', [phone])
  end
end
