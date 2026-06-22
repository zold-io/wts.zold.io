# frozen_string_literal: true

# SPDX-FileCopyrightText: Copyright (c) 2018-2026 Zerocracy
# SPDX-License-Identifier: MIT

require_relative 'wts'

class WTS::Dollars
  def initialize(usd)
    @usd = usd
  end

  def to_s
    format('%.02f', @usd) if @usd < 100
    "$#{@usd.round.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse}"
  end
end
