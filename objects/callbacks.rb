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

# Callbacks.
# Author:: Yegor Bugayenko (yegor256@gmail.com)
# Copyright:: Copyright (c) 2018 Yegor Bugayenko
# License:: MIT
class Callbacks
  def initialize(pgsql, log: Log::NULL)
    @pgsql = pgsql
    @log = log
  end

  # Adds a new callback
  def add(login, wallet, prefix, regexp, uri)
    puts @pgsql.exec('SELECT * FROM callback')
    # exit
    total = @pgsql.exec('SELECT COUNT(*) FROM callback WHERE login = $1', [login])[0]['count'].to_i
    raise UserError, "You have too many of them already: #{total}" if total >= 8
    cid = @pgsql.exec(
      [
        'INSERT INTO callback (login, wallet, prefix, regexp, uri)',
        'VALUES ($1, $2, $3, $4, $5)',
        'RETURNING id'
      ].join(' '),
      [login, wallet, prefix, regexp, uri]
    )[0]['id'].to_i
    @log.info("New callback ##{cid} registered by @#{login} for wallet #{wallet}, \
prefix \"#{prefix}\", regexp #{regexp}, and URI: #{uri}")
    cid
  end

  # Returns the list of IDs of matches found
  def match(wallet, prefix, details)
    found = []
    @pgsql.exec('SELECT * FROM callback WHERE wallet = $1 AND prefix = $2', [wallet, prefix]).each do |r|
      next unless Regexp.new(r['regexp']).match?(details)
      id = @pgsql.exec(
        'INSERT INTO match (callback) VALUES ($1) ON CONFLICT (callback) DO NOTHING RETURNING id',
        [r['id'].to_i]
      )
      next if id.empty?
      mid = id[0]['id'].to_i
      found << mid
      @log.info("Callback ##{r['id']} just matched in #{wallet}/#{prefix} with \"#{details}\", match ##{mid}")
    end
    found
  end

  def fetch(login)
    @pgsql.exec(
      [
        'SELECT callback.*, match.created AS matched FROM callback',
        'LEFT JOIN match ON match.callback = callback.id',
        'WHERE login = $1'
      ].join(' '),
      [login]
    )
  end

  # Ping them all.
  def ping
    @pgsql.exec('DELETE FROM callback WHERE created < NOW() - INTERVAL \'24 HOURS\'')
    @pgsql.exec(
      [
        'DELETE FROM callback WHERE id IN',
        '(SELECT callback FROM match WHERE created < NOW() - INTERVAL \'4 HOURS\')'
      ].join(' ')
    )
    @pgsql.exec('SELECT callback.* FROM callback JOIN match ON callback.id = match.callback').each do |r|
      login = r['login']
      cid = r['id'].to_i
      txns = yield(login, Zold::Id.new(r['wallet']), r['prefix'], Regexp.new(r['regexp']))
      txns.each do |t|
        args = {
          callback: cid,
          login: login,
          regexp: r['regexp'],
          wallet: r['wallet'].to_s,
          id: t.id,
          prefix: t.prefix,
          source: t.bnf.to_s,
          amount: t.amount.to_i,
          details: t.details
        }
        res = Zold::Http.new(uri: r['uri'] + '?' + args.map { |k, v| "#{k}=#{CGI.escape(v.to_s)}" }.join('&')).get
        msg = "The callback ##{cid} of @#{login} "
        if res.code == 200 && res.body == 'OK'
          @pgsql.exec('DELETE FROM callback WHERE id = $1', [cid])
          @log.info("Callback ##{cid} of @#{login} deleted")
          msg += "success at #{r['uri']}, wallet=#{r['wallet']}, amount=#{t.amount}"
        else
          msg += "failure at #{r['uri']}: #{res.code} #{res.status_line}"
        end
        msg += "; there are still \
#{@pgsql.exec('SELECT COUNT(*) FROM callback WHERE login=$1', [login])[0]['count']} callbacks active"
        @log.info(msg)
      end
    end
  end
end
