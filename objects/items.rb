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
require_relative 'item'
require_relative 'user_error'

#
# Items in AWS DynamoDB.
#
class Items
  def initialize(aws, log: Zold::Log::NULL)
    @aws = aws
    @log = log
  end

  def find_by_btc(btc)
    items = @aws.query(
      table_name: 'zold-wallets',
      index_name: 'btc',
      limit: 1,
      consistent_read: false,
      select: 'ALL_ATTRIBUTES',
      expression_attribute_values: { ':b' => btc },
      key_condition_expression: 'btc=:b'
    ).items
    raise UserError, "There is no user with BTC address #{btc}" if items.empty?
    Item.new(items[0]['login'], @aws, log: @log)
  end

  def all
    @aws.query(
      table_name: 'zold-wallets',
      index_name: 'queue',
      limit: 20,
      consistent_read: false,
      select: 'ALL_ATTRIBUTES',
      expression_attribute_values: { ':a' => 1 },
      key_condition_expression: 'active=:a'
    ).items
  end
end
