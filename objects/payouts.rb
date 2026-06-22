# frozen_string_literal: true

# SPDX-FileCopyrightText: Copyright (c) 2018-2026 Zerocracy
# SPDX-License-Identifier: MIT

require 'loog'

class WTS::Payouts
  def initialize(pgsql, log: Loog::NULL)
    @pgsql = pgsql
    @log = log
  end

  def add(login, id, amount, details)
    pid = @pgsql.exec(
      [
        'INSERT INTO payout (login, wallet, zents, details)',
        'VALUES ($1, $2, $3, $4)',
        'RETURNING id'
      ].join(' '),
      [login, id.to_s, amount.to_i, details]
    )[0]['id'].to_i
    @log.debug(
      "New payout ##{pid} registered by #{login} for wallet #{id}, " \
      "amount #{amount}, and details: \"#{details}\""
    )
    pid
  end

  def all(limit: 50)
    @pgsql.exec('SELECT * FROM payout ORDER BY created DESC LIMIT $1', [limit]).map { |r| map(r) }
  end

  def fetch(login, limit: 50)
    @pgsql.exec(
      'SELECT * FROM payout WHERE login = $1 ORDER BY created DESC LIMIT $2',
      [login, limit]
    ).map { |r| map(r) }
  end

  def consumed(login)
    [summed('24 HOURS', login), summed('7 DAYS', login), summed('31 DAYS', login)].map { |a| a.to_zld(0) }.join('/')
  end

  def allowed?(login, amount, limits = '64/128/256')
    daily_limit, weekly_limit, monthly_limit = limits.split('/')
    daily_limit = Zold::Amount.new(zld: daily_limit.to_f)
    weekly_limit = Zold::Amount.new(zld: weekly_limit.to_f)
    monthly_limit = Zold::Amount.new(zld: monthly_limit.to_f)
    return false if summed('24 HOURS', login) + amount > daily_limit
    return false if summed('7 DAYS', login) + amount > weekly_limit
    return false if summed('31 DAYS', login) + amount > monthly_limit
    true
  end

  def system_consumed
    [summed('24 HOURS'), summed('7 DAYS'), summed('31 DAYS')].map { |a| a.to_zld(0) }.join('/')
  end

  def safe?(amount, limits = '64/128/256')
    daily_limit, weekly_limit, monthly_limit = limits.split('/')
    daily_limit = Zold::Amount.new(zld: daily_limit.to_f)
    weekly_limit = Zold::Amount.new(zld: weekly_limit.to_f)
    monthly_limit = Zold::Amount.new(zld: monthly_limit.to_f)
    return false if summed('24 HOURS') + amount > daily_limit
    return false if summed('7 DAYS') + amount > weekly_limit
    return false if summed('31 DAYS') + amount > monthly_limit
    true
  end

  private

  def summed(interval, login = nil)
    Zold::Amount.new(
      zents: @pgsql.exec(
        format(
          "SELECT SUM(zents) FROM payout WHERE %<cond>screated > NOW() - INTERVAL '%<interval>s'",
          cond: login.nil? ? '' : 'login = $1 AND ',
          interval: interval
        ),
        [login].compact
      )[0]['sum'].to_i
    )
  end

  def map(r)
    {
      id: r['id'].to_i,
      login: r['login'],
      wallet: Zold::Id.new(r['wallet']),
      amount: Zold::Amount.new(zents: r['zents'].to_i),
      details: r['details'],
      created: Time.parse(r['created'])
    }
  end
end
