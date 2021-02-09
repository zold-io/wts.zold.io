# Copyright (c) 2018-2021 Zold
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

require 'zold/log'

# Payouts.
# Author:: Yegor Bugayenko (yegor256@gmail.com)
# Copyright:: Copyright (c) 2018 Yegor Bugayenko
# License:: MIT
class WTS::Payouts
  def initialize(pgsql, log: Zold::Log::NULL)
    @pgsql = pgsql
    @log = log
  end

  # Add a new one, which just happened.
  def add(login, id, amount, details)
    pid = @pgsql.exec(
      [
        'INSERT INTO payout (login, wallet, zents, details)',
        'VALUES ($1, $2, $3, $4)',
        'RETURNING id'
      ].join(' '),
      [login, id.to_s, amount.to_i, details]
    )[0]['id'].to_i
    @log.debug("New payout ##{pid} registered by #{login} for wallet #{id}, \
amount #{amount}, and details: \"#{details}\"")
    pid
  end

  def fetch_all(limit: 50)
    @pgsql.exec('SELECT * FROM payout ORDER BY created DESC LIMIT $1', [limit]).map { |r| map(r) }
  end

  def fetch(login, limit: 50)
    @pgsql.exec(
      'SELECT * FROM payout WHERE login = $1 ORDER BY created DESC LIMIT $2',
      [login, limit]
    ).map { |r| map(r) }
  end

  def consumed(login)
    daily = Zold::Amount.new(
      zents: @pgsql.exec(
        'SELECT SUM(zents) FROM payout WHERE login = $1 AND created > NOW() - INTERVAL \'24 HOURS\'',
        [login]
      )[0]['sum'].to_i
    )
    weekly = Zold::Amount.new(
      zents: @pgsql.exec(
        'SELECT SUM(zents) FROM payout WHERE login = $1 AND created > NOW() - INTERVAL \'7 DAYS\'',
        [login]
      )[0]['sum'].to_i
    )
    monthly = Zold::Amount.new(
      zents: @pgsql.exec(
        'SELECT SUM(zents) FROM payout WHERE login = $1 AND created > NOW() - INTERVAL \'31 DAYS\'',
        [login]
      )[0]['sum'].to_i
    )
    "#{daily.to_zld(0)}/#{weekly.to_zld(0)}/#{monthly.to_zld(0)}"
  end

  # Still allowed to send a payout for this amount to this user?
  def allowed?(login, amount, limits = '64/128/256')
    daily_limit, weekly_limit, monthly_limit = limits.split('/')
    daily_limit = Zold::Amount.new(zld: daily_limit.to_f)
    weekly_limit = Zold::Amount.new(zld: weekly_limit.to_f)
    monthly_limit = Zold::Amount.new(zld: monthly_limit.to_f)
    daily = Zold::Amount.new(
      zents: @pgsql.exec(
        'SELECT SUM(zents) FROM payout WHERE login = $1 AND created > NOW() - INTERVAL \'24 HOURS\'',
        [login]
      )[0]['sum'].to_i
    )
    return false if daily + amount > daily_limit
    weekly = Zold::Amount.new(
      zents: @pgsql.exec(
        'SELECT SUM(zents) FROM payout WHERE login = $1 AND created > NOW() - INTERVAL \'7 DAYS\'',
        [login]
      )[0]['sum'].to_i
    )
    return false if weekly + amount > weekly_limit
    monthly = Zold::Amount.new(
      zents: @pgsql.exec(
        'SELECT SUM(zents) FROM payout WHERE login = $1 AND created > NOW() - INTERVAL \'31 DAYS\'',
        [login]
      )[0]['sum'].to_i
    )
    return false if monthly + amount > monthly_limit
    true
  end

  def system_consumed
    daily = Zold::Amount.new(
      zents: @pgsql.exec(
        'SELECT SUM(zents) FROM payout WHERE created > NOW() - INTERVAL \'24 HOURS\''
      )[0]['sum'].to_i
    )
    weekly = Zold::Amount.new(
      zents: @pgsql.exec(
        'SELECT SUM(zents) FROM payout WHERE created > NOW() - INTERVAL \'7 DAYS\''
      )[0]['sum'].to_i
    )
    monthly = Zold::Amount.new(
      zents: @pgsql.exec(
        'SELECT SUM(zents) FROM payout WHERE created > NOW() - INTERVAL \'31 DAYS\''
      )[0]['sum'].to_i
    )
    "#{daily.to_zld(0)}/#{weekly.to_zld(0)}/#{monthly.to_zld(0)}"
  end

  # Is it safe to send that money now?
  def safe?(amount, limits = '64/128/256')
    daily_limit, weekly_limit, monthly_limit = limits.split('/')
    daily_limit = Zold::Amount.new(zld: daily_limit.to_f)
    weekly_limit = Zold::Amount.new(zld: weekly_limit.to_f)
    monthly_limit = Zold::Amount.new(zld: monthly_limit.to_f)
    daily = Zold::Amount.new(
      zents: @pgsql.exec(
        'SELECT SUM(zents) FROM payout WHERE created > NOW() - INTERVAL \'24 HOURS\''
      )[0]['sum'].to_i
    )
    return false if daily + amount > daily_limit
    weekly = Zold::Amount.new(
      zents: @pgsql.exec(
        'SELECT SUM(zents) FROM payout WHERE created > NOW() - INTERVAL \'7 DAYS\''
      )[0]['sum'].to_i
    )
    return false if weekly + amount > weekly_limit
    monthly = Zold::Amount.new(
      zents: @pgsql.exec(
        'SELECT SUM(zents) FROM payout WHERE created > NOW() - INTERVAL \'31 DAYS\''
      )[0]['sum'].to_i
    )
    return false if monthly + amount > monthly_limit
    true
  end

  private

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
