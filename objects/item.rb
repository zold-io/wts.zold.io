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

require 'zold/key'
require 'zold/id'
require 'zold/log'
require_relative 'keygap'
require_relative 'user_error'

#
# Item in AWS DynamoDB.
#
class Item
  attr_reader :login

  def initialize(login, aws, log: Zold::Log::NULL)
    @login = login.downcase
    @aws = aws
    @log = log
  end

  def exists?
    !items.empty?
  end

  # Creates a record in DynamoDB and generates a unique keygap.
  # +id+:: Wallet iD
  # +key+:: Private RSA key
  # +length+:: Length of keygap to use (don't change it without a necessity)
  def create(id, key, length: 16)
    pem, keygap = Keygap.new.extract(key.to_s, length)
    @aws.put_item(
      table_name: 'zold-wallets',
      item: {
        'login' => @login,
        'id' => id.to_s,
        'pem' => pem,
        'keygap' => keygap
      }
    )
    @log.info("New user @#{@login} created, wallet ID is #{id}, \
keygap is '#{keygap[0, 2]}#{'.' * (keygap.length - 2)}'")
    keygap
  end

  # Return private key as Zold::Key
  def key(keygap)
    key = read['pem']
    raise "There is no key for some reason for user @#{@login}" if key.nil?
    key = Keygap.new.merge(key, keygap)
    @log.debug("The private key of @#{@login} reassembled: #{key.to_s.length} chars")
    key
  end

  # Return private key as text
  def raw_key
    key = read['pem']
    raise "There is no key for some reason for user @#{@login}" if key.nil?
    key
  end

  # Return Wallet ID as Zold::Id
  def id
    Zold::Id.new(read['id'])
  end

  # Returns user Keygap temporarily stored in the database. We should not
  # keep it here for too long. Once the user confirms that the keygap has
  # been stored safely, we should call wipe(), which will remove the
  # keygap from the database.
  def keygap
    keygap = read['keygap']
    raise "The user @#{@login} doesn't have a keygap anymore" if keygap.nil?
    @log.debug("The keygap of @#{@login} retrieved")
    keygap
  end

  # Returns TRUE if the keygap is absent in the item
  def wiped?
    read['keygap'].nil?
  end

  # Remove the keygap from DynamoDB
  def wipe(keygap)
    item = read
    if keygap != item['keygap']
      raise "Keygap '#{keygap}' of @#{@login} doesn't match \
'#{item['keygap'][0, 2]}#{'.' * (item['keygap'].length - 2)}'"
    end
    item.delete('keygap')
    @aws.put_item(table_name: 'zold-wallets', item: item)
    @log.debug("The keygap of @#{@login} was destroyed")
  end

  # Returns BTC address if possible to get it (one of the existing ones),
  # otherwise generate a new one, using the block.
  def btc
    item = read
    return item['btc'] if item['btc'] && Time.at(item['assigned'].to_i) > Time.now - 60 * 60
    found = @aws.query(
      table_name: 'zold-wallets',
      limit: 1,
      index_name: 'queue',
      select: 'ALL_ATTRIBUTES',
      consistent_read: false,
      expression_attribute_values: { ':a' => 1 },
      key_condition_expression: 'active=:a'
    ).items
    if found.empty? || Time.at(found[0]['assigned'].to_i) > Time.now - 60 * 60
      item['btc'] = yield
    else
      expired = found[0]
      item['btc'] = expired['btc']
      expired.delete('btc')
      expired['active'] = 0
      @aws.put_item(table_name: 'zold-wallets', item: expired)
    end
    item['assigned'] = Time.now.to_i
    item['active'] = 1
    @aws.put_item(table_name: 'zold-wallets', item: item)
    item['btc']
  end

  private

  def read
    item = items[0]
    raise "There is no item in DynamoDB for @#{@login}" if item.nil?
    item
  end

  def items
    @aws.query(
      table_name: 'zold-wallets',
      consistent_read: true,
      limit: 1,
      select: 'ALL_ATTRIBUTES',
      expression_attribute_values: { ':u' => @login },
      key_condition_expression: 'login=:u'
    ).items
  end
end
