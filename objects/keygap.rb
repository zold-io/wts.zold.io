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

#
# Keygap code.
#
class WTS::Keygap
  # Extracts a random keygap and returns an array of [pem, keygap]
  def extract(key, length = 16)
    pem = key.to_s
    keygap = ''
    until keygap =~ /^[a-zA-Z0-9]+$/ && !keygap.include?("\n")
      start = Random.new.rand(pem.length - length)
      keygap = pem[start..(start + length - 1)]
    end
    [pem.sub(keygap, '*' * length), keygap]
  end

  # Returns Zold::Key
  def merge(pem, keygap)
    Zold::Key.new(text: pem.sub('*' * keygap.length, keygap))
  end
end
