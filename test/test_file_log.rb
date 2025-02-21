# SPDX-FileCopyrightText: Copyright (c) 2018-2025 Zerocracy
# SPDX-License-Identifier: MIT

require 'minitest/autorun'
require_relative 'test__helper'
require_relative '../objects/file_log'

class WTS::FileLogTest < Minitest::Test
  def test_writes_and_reads
    Dir.mktmpdir 'test' do |dir|
      log = WTS::FileLog.new(File.join(dir, 'a/b/c/d.txt'))
      log.info('How are you, dude?')
      assert(log.content.include?('dude'))
    end
  end
end
