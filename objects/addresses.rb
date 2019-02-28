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

require 'zold/log'
require_relative 'pgsql'
require_relative 'user_error'

# Incoming Bitcoin addresses.
# Author:: Yegor Bugayenko (yegor256@gmail.com)
# Copyright:: Copyright (c) 2018 Yegor Bugayenko
# License:: MIT
class Addresses
  def initialize(pgsql, log: Log::NULL)
    @pgsql = pgsql
    @log = log
  end

  def find_user(hash)
    found = @pgsql.exec('SELECT login FROM address WHERE hash = $1', [hash])
    raise UserError, "There is no user who would expect #{hash}" if found.empty?
    found[0]['login']
  end

  def all
    @pgsql.exec('SELECT * FROM address').map do |r|
      {
        hash: r['hash'],
        login: r['login'],
        assigned: Time.parse(r['assigned']),
        arrived: r['arrived'].nil? ? nil : Time.parse(r['arrived'])
      }
    end
  end

  # Returns BTC address if possible to get it (one of the existing ones),
  # otherwise generate a new one, using the block.
  def acquire(login, btc, lifetime: 30 * 60)
    mine = @pgsql.exec('SELECT * FROM address WHERE login = $1', [login])
    unless mine.empty?
      age = Time.now - Time.parse(mine[0]['assigned'])
      return mine[0]['hash'] if age < lifetime
      return mine[0]['hash'] if mine[0]['arrived'] && age < lifetime * 10
    end
    friend = candidates(login, lifetime)[0]
    if friend.nil?
      addr = btc.create
      friend = ".reserve-#{rand(9999)}"
      @pgsql.exec('INSERT INTO address (hash, login, pvt) VALUES ($1, $2, $3)', [addr[:hash], friend, addr[:pvt]])
    end
    if mine.empty?
      move(friend, login)
    else
      swap(login, friend)
    end
  end

  # Removes the used BTC address entirely (when funds received).
  def destroy(hash, login)
    owner = find_user(hash)
    raise UserError, "The hash #{hash} doesn't belong to #{login}, but instead to #{owner}" unless owner == login
    r = @pgsql.exec('SELECT * FROM address WHERE hash = $1', [hash])[0]
    raise UserError, "The hash #{hash} hasn't arrived, why destroying?" unless r['arrived']
    @pgsql.exec('DELETE FROM address WHERE hash = $1', [hash])
    yield r['pvt']
  end

  # Mark this BTC as "in processing" and don't give it to anyone else
  def arrived(hash, login)
    owner = find_user(hash)
    raise UserError, "The hash #{hash} doesn't belong to #{login}, but instead to #{owner}" unless owner == login
    r = @pgsql.exec('SELECT * FROM address WHERE hash = $1', [hash])[0]
    raise UserError, "The hash #{hash} is already in arrival" if r['arrived']
    @pgsql.exec('UPDATE address SET arrived = NOW() WHERE hash = $1', [hash])
  end

  # Get BTC assignment time.
  def mtime(login)
    Time.parse(@pgsql.exec('SELECT assigned FROM address WHERE login = $1', [login])[0]['assigned'])
  end

  # Is something already arrived to this address?
  def arrived?(login)
    !@pgsql.exec('SELECT arrived FROM address WHERE login = $1', [login])[0]['arrived'].nil?
  end

  private

  # Find the best candidates (list of logins) to take the BTC address away from him
  # and give it to someone else
  def candidates(mine, lifetime)
    query = 'SELECT * FROM address WHERE login != $1 AND arrived IS NULL ORDER BY assigned'
    rows = @pgsql.exec(query, [mine]).select do |r|
      age = Time.now - Time.parse(r['assigned'])
      r['arrived'] ? age > lifetime * 10 : age > lifetime
    end
    rows.map { |r| r['login'] }
  end

  # Swap hashes and return the one taken from the friend
  def swap(login, friend)
    raise "Can't move itself: #{friend}" if friend == login
    @pgsql.connect do |c|
      c.transaction do |con|
        rows = con.exec_params('SELECT * FROM address WHERE login = $1', [login])
        raise "Source user #{login} has no BTC address assigned" if rows.ntuples.zero?
        mine = rows[0]
        con.exec_params('DELETE FROM address WHERE login = $1', [login])
        rows = con.exec_params('SELECT * FROM address WHERE login = $1', [friend])
        raise "Target user #{friend} has no BTC address assigned" if rows.ntuples.zero?
        theirs = rows[0]
        con.exec_params('DELETE FROM address WHERE login = $1', [friend])
        con.exec_params(
          'INSERT INTO address (hash, login, pvt) VALUES ($1, $2, $3)',
          [mine['hash'], friend, mine['pvt']]
        )
        con.exec_params(
          'INSERT INTO address (hash, login, pvt) VALUES ($1, $2, $3)',
          [theirs['hash'], login, theirs['pvt']]
        )
        theirs['hash']
      end
    end
  end

  # Move from friend to me (and delete the friend)
  def move(friend, login)
    raise "Can't move itself: #{friend}" if friend == login
    @pgsql.connect do |c|
      c.transaction do |con|
        theirs = con.exec_params('SELECT * FROM address WHERE login = $1', [friend])[0]
        con.exec_params('DELETE FROM address WHERE login = $1', [friend])
        con.exec_params(
          'INSERT INTO address (hash, login, pvt) VALUES ($1, $2, $3)',
          [theirs['hash'], login, theirs['pvt']]
        )
        theirs['hash']
      end
    end
  end
end
