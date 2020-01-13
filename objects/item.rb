# Copyright (c) 2018-2020 Zerocracy, Inc.
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

require 'zold/key'
require 'zold/id'
require 'zold/log'
require_relative 'wts'
require_relative 'keygap'
require_relative 'tags'
require_relative 'user_error'

#
# Item in database.
#
class WTS::Item
  attr_reader :login

  def initialize(login, pgsql, log: Zold::Log::NULL)
    @login = login.downcase
    @pgsql = pgsql
    @log = log
  end

  # Tags.
  def tags
    WTS::Tags.new(@login, @pgsql, log: @log)
  end

  def exists?
    !@pgsql.exec('SELECT * FROM item WHERE login = $1', [login]).empty?
  end

  # Creates a record in the database and generates a unique keygap.
  # +id+:: Wallet iD
  # +key+:: Private RSA key
  # +length+:: Length of keygap to use (don't change it without a necessity)
  def create(id, key, length: 16)
    pem, keygap = WTS::Keygap.new.extract(key.to_s, length)
    @pgsql.exec(
      [
        'INSERT INTO item (login, id, pem) VALUES ($1, $2, $3)',
        'ON CONFLICT (login) DO UPDATE SET id = $2, pem = $3'
      ].join(' '),
      [@login, id.to_s, pem]
    )
    @pgsql.exec(
      [
        'INSERT INTO keygap (login, keygap) VALUES ($1, $2)',
        'ON CONFLICT (login) DO UPDATE SET keygap = $2'
      ].join(' '),
      [@login, keygap]
    )
    @log.info("New user #{@login} created, wallet ID is #{id}, \
keygap is '#{keygap[0, 2]}#{'.' * (keygap.length - 2)}'")
    keygap
  end

  # This is used during migration to a new wallet.
  def replace_id(id)
    @pgsql.exec('UPDATE item SET id = $1 WHERE login = $2', [id, @login])
  end

  # Return private key as Zold::Key
  def key(keygap)
    key = WTS::Keygap.new.merge(raw_key, keygap)
    @log.debug("The private key of #{@login} reassembled: #{key.to_s.length} chars")
    key
  end

  # Return private key as text
  def raw_key
    @pgsql.exec('SELECT pem FROM item WHERE login = $1', [@login])[0]['pem']
  end

  # Return Wallet ID as Zold::Id
  def id
    row = @pgsql.exec('SELECT id FROM item WHERE login = $1', [@login])[0]
    raise "User #{@login} is not yet registered" if row.nil?
    Zold::Id.new(row['id'])
  end

  # Returns user Keygap temporarily stored in the database. We should not
  # keep it here for too long. Once the user confirms that the keygap has
  # been stored safely, we should call wipe(), which will remove the
  # keygap from the database.
  def keygap
    row = @pgsql.exec('SELECT keygap FROM keygap WHERE login = $1', [@login])[0]
    raise "The user #{@login} doesn't have a keygap anymore" if row.nil?
    keygap = row['keygap']
    @log.debug("The keygap of #{@login} retrieved")
    keygap
  end

  # Returns TRUE if the keygap is absent in the item
  def wiped?
    @pgsql.exec('SELECT keygap FROM keygap WHERE login = $1', [@login]).empty?
  end

  # Remove the keygap from DynamoDB
  def wipe(keygap)
    before = keygap
    if keygap != before
      raise "Keygap '#{keygap}' of #{@login} doesn't match '#{before[0, 2]}#{'.' * (before.length - 2)}'"
    end
    @pgsql.exec('DELETE FROM keygap WHERE login = $1', [@login])
    @log.debug("The keygap of #{@login} was destroyed")
  end

  def touch
    @pgsql.exec('UPDATE item SET touched = NOW() WHERE login = $1', [@login])
  end
end
