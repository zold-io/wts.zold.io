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
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

require 'minitest/autorun'
require 'webmock/minitest'
require 'zold/remotes'
require_relative 'test__helper'
require_relative '../objects/gl'

class WTS::GlTest < Minitest::Test
  def test_scan_and_fetch
    WebMock.allow_net_connect!
    Dir.mktmpdir 'test' do |dir|
      remotes = Zold::Remotes.new(file: File.join(dir, 'remotes.csv'))
      remotes.clean
      id = rand(1000)
      stub_request(:get, 'http://localhost:4096/ledger.json').to_return(
        body: JSON.pretty_generate(
          [
            {
              id: id,
              date: Time.now.utc.iso8601,
              source: '0000111122223333',
              target: 'ffffeeeeddddcccc',
              amount: 9_999_999_999_999,
              prefix: 'NOPREFIX',
              details: 'for pizza'
            },
            {
              id: id,
              date: Time.now.utc.iso8601,
              source: '0000111122223333',
              target: 'aaaa5555aaaa5555',
              amount: 2048,
              prefix: 'NOPREFIX',
              details: 'for another pizza'
            }
          ]
        )
      )
      remotes.add('localhost', 4096)
      gl = WTS::Gl.new(test_pgsql, log: test_log)
      gl.scan(remotes) do |t|
        assert_equal(id, t[:id], t)
        assert_equal("#{t[:source]}:#{t[:id]}", t[:tid], t)
      end
      assert(gl.fetch(query: '0000111122223333').count.positive?)
      row = gl.fetch[0]
      assert_equal(id, row[:id], row)
      assert_equal('0000111122223333', row[:source].to_s, row)
      assert_equal('ffffeeeeddddcccc', row[:target].to_s, row)
      assert(row[:date] > Time.now - 60, row)
      assert_equal(9_999_999_999_999, row[:amount].to_i, row)
      assert_equal('for pizza', row[:details], row)
    end
  end

  def test_calc_volume
    gl = WTS::Gl.new(test_pgsql, log: test_log)
    assert(!gl.volume(4).nil?)
  end
end
