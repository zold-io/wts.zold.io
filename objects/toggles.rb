# frozen_string_literal: true

# SPDX-FileCopyrightText: Copyright (c) 2018-2026 Zerocracy
# SPDX-License-Identifier: MIT

require 'loog'
require 'time'
require_relative 'user_error'

class WTS::Toggles
  def initialize(pgsql, log: Loog::NULL)
    @pgsql = pgsql
    @log = log
  end

  def set(key, value)
    if value.empty?
      @pgsql.exec('DELETE FROM toggle WHERE key = $1', [key])
    else
      @pgsql.exec(
        [
          'INSERT INTO toggle (key, value)',
          'VALUES ($1, $2)',
          'ON CONFLICT (key) DO UPDATE SET value = $2, updated = NOW()'
        ].join(' '),
        [key, value]
      )
    end
  end

  def get(key, default = '')
    r = @pgsql.exec('SELECT value FROM toggle WHERE key = $1', [key])[0]
    return default if r.nil?
    r['value']
  end

  def list
    @pgsql.exec('SELECT * FROM toggle ORDER BY key').map do |r|
      {
        key: r['key'],
        value: r['value'],
        updated: Time.parse(r['updated'])
      }
    end
  end
end
