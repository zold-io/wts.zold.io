# SPDX-FileCopyrightText: Copyright (c) 2018-2025 Zerocracy
# SPDX-License-Identifier: MIT

require 'zold/log'
require_relative 'user_error'

#
# Ticks in AWS DynamoDB.
#
class WTS::Ticks
  def initialize(pgsql, log: Zold::Log::NULL)
    @pgsql = pgsql
    @log = log
  end

  # Already exists for the current time?
  def exists?(key, seconds = 6 * 60 * 60)
    !@pgsql.exec(
      "SELECT FROM tick WHERE key = $1 AND created > NOW() - INTERVAL '#{seconds} SECONDS'",
      [key]
    ).empty?
  end

  # Add ticks.
  def add(hash)
    hash.each do |k, v|
      @pgsql.exec('INSERT INTO tick (key, value) VALUES ($1, $2)', [k, v])
    end
  end

  # Fetch them all.
  def fetch(key)
    @pgsql.exec('SELECT * FROM tick WHERE key = $1', [key]).map do |r|
      { key: r['key'], value: r['value'].to_f, created: Time.parse(r['created']) }
    end
  end

  # Fetch the latest.
  def latest(key)
    row = @pgsql.exec('SELECT * FROM tick WHERE key = $1 ORDER BY created DESC LIMIT 1', [key])[0]
    raise WTS::UserError, "E182: No ticks found for #{key}" if row.nil?
    row['value'].to_f
  end
end
