# SPDX-FileCopyrightText: Copyright (c) 2018-2025 Zerocracy
# SPDX-License-Identifier: MIT

require_relative 'wts'

# Current ZLD/BTC rate.
# Author:: Yegor Bugayenko (yegor256@gmail.com)
# Copyright:: Copyright (c) 2018 Yegor Bugayenko
# License:: MIT
class WTS::Rate
  def initialize(toggles)
    @toggles = toggles
  end

  def to_f
    @toggles.get('rate', '0.00025').to_f
  end
end
