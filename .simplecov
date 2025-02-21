# SPDX-FileCopyrightText: Copyright (c) 2018-2025 Zerocracy
# SPDX-License-Identifier: MIT

SimpleCov.start do
  add_filter '/test/'
  add_filter '/features/'
end
SimpleCov.formatter = if Gem.win_platform?
  SimpleCov::Formatter::MultiFormatter[
    SimpleCov::Formatter::HTMLFormatter
  ]
else
  SimpleCov::Formatter::MultiFormatter.new(
    SimpleCov::Formatter::HTMLFormatter
  )
end
