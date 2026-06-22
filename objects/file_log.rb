# frozen_string_literal: true

# SPDX-FileCopyrightText: Copyright (c) 2018-2026 Zerocracy
# SPDX-License-Identifier: MIT

class WTS::FileLog
  def initialize(file)
    @file = file
    FileUtils.mkdir_p(File.dirname(@file))
  end

  def content
    if File.exist?(@file)
      File.read(@file)
    else
      'There is no log as of yet...'
    end
  end

  def debug(msg); end

  def debug?
    false
  end

  def info(msg)
    print(msg)
  end

  def info?
    true
  end

  def error(msg)
    print("ERROR: #{msg}")
  end

  private

  def print(msg)
    File.open(@file, 'a') { |f| f.puts(msg) }
  end
end
