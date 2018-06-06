# Copyright (c) 2018 Yegor Bugayenko
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

#
# Item in AWS DynamoDB.
#
class Item
  def initialize(login, aws, log: Zold::Log::Quiet.new)
    raise 'Login can\'t be nil' if login.nil?
    @login = login
    raise 'AWS can\'t be nil' if aws.nil?
    @aws = aws
    raise 'Log can\'t be nil' if log.nil?
    @log = log
  end

  def exists?
    !items.empty?
  end

  # Creates a record in DynamoDB and generates a unique pass code.
  # +id+:: Wallet iD
  # +key+:: Private RSA key
  # +length+:: Length of pass to use (don't change it without a necessity)
  def create(id, key, length: 8)
    raise 'ID can\'t be nil' if id.nil?
    raise 'Key can\'t be nil' if key.nil?
    raise 'Length can\'t be nil' if length.nil?
    raise "Item already exists for @#{login}" if exists?
    pem = key.to_s
    pass = extract(pem, length)
    @aws.put_item(
      table_name: 'zold-wallets',
      item: {
        'login' => @login,
        'id' => id.to_s,
        'key' => pem.sub(pass, '*' * length),
        'pass' => pass
      }
    )
    @log.debug("New user @#{@login} created, ID=#{id}")
    pass
  end

  # Return private key as Zold::Key
  def key(pass)
    raise 'Pass can\'t be nil' if pass.nil?
    key = read['key']
    raise "There is no key for some reason for user @#{@login}" if key.nil?
    key = Zold::Key.new(text: key.sub('*' * pass.length, pass))
    @log.debug("The private key of @#{@login} reassembled: #{key.to_s.length} chars")
    key
  end

  # Return private key as text
  def raw_key
    key = read['key']
    raise "There is no key for some reason for user @#{@login}" if key.nil?
    key
  end

  # Return Wallet ID as Zold::Id
  def id
    id = Zold::Id.new(read['id'])
    @log.debug("The ID of @#{@login} retrieved: #{id}")
    id
  end

  def pass
    pass = read['pass']
    raise "The user @#{@login} doesn't have a pass anymore" if pass.nil?
    @log.debug("The pass code of @#{@login} retrieved")
    pass
  end

  # Returns TRUE if the pass is absent in the item
  def wiped?
    read['pass'].nil?
  end

  # Remove the pass code from DynamoDB
  def wipe(pass)
    raise 'Pass can\'t be nil' if pass.nil?
    item = read
    @aws.put_item(
      table_name: 'zold-wallets',
      item: {
        'login' => @login,
        'id' => item['id'],
        'key' => item['key']
      }
    )
    @log.debug("The pass code of @#{@login} was destroyed")
  end

  private

  def extract(text, length)
    pass = ''
    until pass =~ /^[a-zA-Z0-9]+$/
      start = Random.new.rand(text.length - length)
      pass = text[start..(start + length - 1)]
    end
    pass
  end

  def read
    item = items[0]
    raise "There is no item in DynamoDB for @#{@login}" if item.nil?
    item
  end

  def items
    @aws.query(
      table_name: 'zold-wallets',
      limit: 1,
      select: 'ALL_ATTRIBUTES',
      expression_attribute_values: { ':u' => @login },
      key_condition_expression: 'login=:u'
    ).items
  end
end
