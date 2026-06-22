# frozen_string_literal: true

# SPDX-FileCopyrightText: Copyright (c) 2018-2026 Zerocracy
# SPDX-License-Identifier: MIT

require 'loog'
require 'securerandom'
require_relative 'user_error'

class WTS::Tokens
  def initialize(pgsql, log: Loog::NULL)
    @pgsql = pgsql
    @log = log
  end

  def get(login)
    row = @pgsql.exec('SELECT token FROM token WHERE login = $1', [login])[0]
    return row['token'] unless row.nil?
    reset(login)
  end

  def reset(login)
    token = SecureRandom.uuid.gsub(/[^a-f0-9]/, '')
    @pgsql.exec(
      'INSERT INTO token (login, token) VALUES ($1, $2) ON CONFLICT (login) DO UPDATE SET token = $2',
      [login, token]
    )
    token
  end
end
