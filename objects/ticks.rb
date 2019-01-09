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

#
# Ticks in AWS DynamoDB.
#
class Ticks
  def initialize(aws, log: Zold::Log::NULL)
    @aws = aws
    @log = log
  end

  # Already exists for the current time?
  def exists?(age = 6 * 60 * 60)
    !@aws.query(
      table_name: 'zold-ticks',
      consistent_read: true,
      limit: 1,
      expression_attribute_names: { '#time' => 'time' },
      expression_attribute_values: { ':t' => 'tick', ':i' => ((Time.now.to_f - age) * 1000).to_i },
      key_condition_expression: 'tick = :t and #time > :i'
    ).items.empty?
  end

  # Add tick.
  def add(hash)
    @aws.put_item(
      table_name: 'zold-ticks',
      item: {
        'tick' => 'tick',
        'time' => (Time.now.to_f * 1000).to_i
      }.merge(hash)
    )
  end

  # Fetch them all.
  def fetch
    @aws.scan(
      table_name: 'zold-ticks',
      select: 'ALL_ATTRIBUTES'
    ).items
  end
end
