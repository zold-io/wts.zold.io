# SPDX-FileCopyrightText: Copyright (c) 2018-2025 Zerocracy
# SPDX-License-Identifier: MIT

require_relative 'wts'

# Number as dollars.
# Author:: Yegor Bugayenko (yegor256@gmail.com)
# Copyright:: Copyright (c) 2018 Yegor Bugayenko
# License:: MIT
class WTS::Dollars
  def initialize(usd)
    @usd = usd
  end

  def to_s
    txt = @usd.round.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse
    txt = format('%.02f', @usd) if @usd < 100
    '$' + txt
  end
end
