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
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

require 'minitest/autorun'
require_relative 'test__helper'
require_relative '../objects/btc'

class BtcTest < Minitest::Test
  def test_creates_address
    skip
    btc = Btc.new(
      'xpub6D2...',
      '9049a412-...',
      log: test_log
    )
    address = btc.create('jeff')
    assert_equal(34, address.length)
  end

  def test_validates_txn
    btc = Btc.new('', '', log: test_log)
    assert(
      btc.exists?(
        'c3c0a51ff985618dd8373eadf3540fd1bea44d676452dbab47fe0cc07209547d',
        27_900,
        '1N1R2HP9JD4LvAtp7rTkpRqF19GH7PH2ZF'
      )
    )
  end

  def test_validates_invalid_txn
    btc = Btc.new('', '', log: test_log)
    assert(
      !btc.exists?(
        'c3c0a51ff985618dd8373eadf3540fd1bea44d676452dbab47fe0cc07209547d',
        500,
        '1N1R2HP9JD4LvAtp7rTkpRqF19GH7PH2ZF'
      )
    )
  end
end
