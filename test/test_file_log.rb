# frozen_string_literal: true

# SPDX-FileCopyrightText: Copyright (c) 2018-2026 Zerocracy
# SPDX-License-Identifier: MIT

require_relative '../objects/file_log'
require_relative 'test__helper'

class WTS::FileLogTest < Minitest::Test
  def test_writes_and_reads
    Dir.mktmpdir('test') do |dir|
      log = WTS::FileLog.new(File.join(dir, 'a/b/c/d.txt'))
      log.info('How are you, dude?')
      assert_includes(log.content, 'dude')
    end
  end
end
