# Copyright (c) 2018-2022 Zold
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

require 'time'
require 'zold/http'
require 'zold/id'
require_relative 'user_error'

# Callbacks.
# Author:: Yegor Bugayenko (yegor256@gmail.com)
# Copyright:: Copyright (c) 2018 Yegor Bugayenko
# License:: MIT
class WTS::Callbacks
  # How many per one user
  MAX = 1024

  def initialize(pgsql, log: Zold::Log::NULL)
    @pgsql = pgsql
    @log = log
  end

  # Adds a new callback
  def add(login, wallet, prefix, regexp, uri, token = 'none', repeat: false, forever: false)
    total = @pgsql.exec('SELECT COUNT(*) FROM callback WHERE login = $1', [login])[0]['count'].to_i
    raise WTS::UserError, "EYou have too many of them already: #{total}" if total >= MAX
    found = @pgsql.exec(
      'SELECT id FROM callback WHERE login = $1 AND wallet = $2 AND prefix = $3 AND regexp = $4 AND uri = $5',
      [login, wallet, prefix, regexp, uri]
    )[0]
    raise WTS::UserErorr, "You already have a callback ##{found['id']} registered with similar params" unless found.nil?
    cid = @pgsql.exec(
      [
        'INSERT INTO callback (login, wallet, prefix, regexp, uri, token, repeat, forever)',
        'VALUES ($1, $2, $3, $4, $5, $6, $7, $8)',
        'RETURNING id'
      ].join(' '),
      [login, wallet, prefix, regexp, uri, token, repeat, forever]
    )[0]['id'].to_i
    @log.debug("New callback ##{cid} registered by #{login} for wallet #{wallet}, \
prefix \"#{prefix}\", regexp #{regexp}, and URI: #{uri}")
    cid
  end

  def restart(id)
    @pgsql.exec('UPDATE match SET failure = NULL WHERE callback=$1', [id])
  end

  # Returns the list of IDs of matches found
  def match(tid, wallet, prefix, details)
    found = []
    @pgsql.exec('SELECT * FROM callback WHERE wallet = $1 AND prefix = $2', [wallet, prefix]).each do |r|
      next unless Regexp.new(r['regexp']).match?(details)
      id = @pgsql.exec(
        'INSERT INTO match (callback, tid) VALUES ($1, $2) ON CONFLICT(tid) DO NOTHING RETURNING id',
        [r['id'].to_i, tid]
      )
      next if id.empty?
      mid = id[0]['id'].to_i
      found << mid
      yield(map(r), mid) if block_given?
    end
    found
  end

  def fetch(login, limit: 50)
    @pgsql.exec(
      [
        'SELECT callback.*, match.created AS matched, match.failure AS failure FROM callback',
        'LEFT JOIN match ON match.callback = callback.id',
        'WHERE login = $1',
        'ORDER BY matched DESC, callback.created DESC',
        'LIMIT $2'
      ].join(' '),
      [login, limit]
    ).map { |r| map(r) }
  end

  # Ping them all.
  def ping
    q = [
      'SELECT callback.*, match.id AS mid',
      'FROM callback',
      'JOIN match ON callback.id = match.callback'
    ].join(' ')
    @pgsql.exec(q).each do |r|
      login = r['login']
      cid = r['id'].to_i
      txns = yield(login, Zold::Id.new(r['wallet']), r['prefix'], Regexp.new(r['regexp']))
      txns.each do |t|
        args = {
          tid: "#{t.bnf}:#{t.id}",
          callback: cid,
          login: login,
          regexp: r['regexp'],
          wallet: r['wallet'].to_s,
          id: t.id,
          prefix: t.prefix,
          source: t.bnf.to_s,
          amount: t.amount.to_i,
          details: t.details,
          token: r['token']
        }
        uri = r['uri'] + '?' + args.map { |k, v| "#{k}=#{CGI.escape(v.to_s)}" }.join('&')
        res = Zold::Http.new(uri: uri).get
        f = failure(res, uri)
        @pgsql.exec(
          'UPDATE match SET failure = $1 WHERE id = $2',
          [f, r['mid'].to_i]
        )
        @log.info("Callback ##{cid} pinged: #{f.inspect}")
      end
    end
  end

  # Repeat all succeeded callbacks.
  def repeat_succeeded
    q = [
      'SELECT match.id FROM callback',
      'JOIN match ON match.callback = callback.id',
      'WHERE match.failure = \'\' AND repeat = true'
    ].join(' ')
    @pgsql.exec(q).each do |r|
      @pgsql.exec('DELETE FROM match WHERE id = $1', [r['id'].to_i])
      yield c if block_given?
    end
  end

  # Delete all succeeded callbacks.
  def delete_succeeded
    q = [
      'SELECT callback.* FROM callback',
      'JOIN match ON match.callback = callback.id',
      'WHERE match.failure = \'\' AND repeat = false'
    ].join(' ')
    @pgsql.exec(q).each do |r|
      c = map(r)
      @pgsql.exec('DELETE FROM callback WHERE id = $1', [c[:id]])
      yield c if block_given?
    end
  end

  # Delete all expired callbacks.
  def delete_expired
    @pgsql.exec('SELECT * FROM callback WHERE created < NOW() - INTERVAL \'24 HOURS\' AND forever = false').each do |r|
      c = map(r)
      @pgsql.exec('DELETE FROM callback WHERE id = $1', [c[:id]])
      yield c if block_given?
    end
  end

  def delete_failed
    q = [
      'SELECT callback.* FROM callback',
      'JOIN match ON match.callback = callback.id',
      'WHERE match.created < NOW() - INTERVAL \'24 HOURS\''
    ].join(' ')
    @pgsql.exec(q).each do |r|
      c = map(r)
      @pgsql.exec('DELETE FROM callback WHERE id = $1', [c[:id]])
      yield c if block_given?
    end
  end

  private

  def failure(res, uri)
    if res.code != 200
      "#{Time.now.utc.iso8601}: HTTP response code at #{uri} was #{res.code} \
instead of 200: #{res.status_line.inspect}"
    elsif res.body != 'OK'
      "#{Time.now.utc.iso8601}: HTTP response body at #{uri} was not equal to 'OK' \
even though response code was 200: #{res.body.inspect}"
    else
      ''
    end
  end

  def map(r)
    {
      id: r['id'].to_i,
      login: r['login'],
      uri: URI(r['uri']),
      wallet: Zold::Id.new(r['wallet']),
      prefix: r['prefix'],
      regexp: Regexp.new(r['regexp']),
      matched: r['matched'] ? Time.parse(r['matched']) : nil,
      failure: r['failure'],
      created: Time.parse(r['created']),
      forever: r['forever'] == 'true',
      repeat: r['repeat'] == 'true'
    }
  end
end
