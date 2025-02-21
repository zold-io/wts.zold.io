# SPDX-FileCopyrightText: Copyright (c) 2018-2025 Zerocracy
# SPDX-License-Identifier: MIT

require 'zold/log'
require 'securerandom'
require_relative 'user_error'

#
# Tokens of users.
#
class WTS::Tokens
  def initialize(pgsql, log: Zold::Log::NULL)
    @pgsql = pgsql
    @log = log
  end

  # API token, if exists. Otherwise, resets it.
  def get(login)
    row = @pgsql.exec('SELECT token FROM token WHERE login = $1', [login])[0]
    return row['token'] unless row.nil?
    reset(login)
  end

  # Sets a new API token to the user.
  def reset(login)
    token = SecureRandom.uuid.gsub(/[^a-f0-9]/, '')
    @pgsql.exec(
      'INSERT INTO token (login, token) VALUES ($1, $2) ON CONFLICT (login) DO UPDATE SET token = $2',
      [login, token]
    )
    token
  end
end
