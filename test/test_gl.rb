# SPDX-FileCopyrightText: Copyright (c) 2018-2025 Zerocracy
# SPDX-License-Identifier: MIT

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
      gl = WTS::Gl.new(t_pgsql, log: t_log)
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
    gl = WTS::Gl.new(t_pgsql, log: t_log)
    assert(!gl.volume(4).nil?)
  end
end
