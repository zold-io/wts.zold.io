# frozen_string_literal: true

# SPDX-FileCopyrightText: Copyright (c) 2018-2026 Zerocracy
# SPDX-License-Identifier: MIT

require_relative 'wts'

class WTS::Rate
  def initialize(toggles)
    @toggles = toggles
  end

  def to_f
    @toggles.get('rate', '0.00025').to_f
  end
end
