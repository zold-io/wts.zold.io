# frozen_string_literal: true

# SPDX-FileCopyrightText: Copyright (c) 2018-2026 Zerocracy
# SPDX-License-Identifier: MIT

require 'zold/key'

class WTS::Keygap
  def extract(key, length = 16)
    pem = key.to_s
    keygap = ''
    until keygap =~ /^[a-zA-Z0-9]+$/ && !keygap.include?("\n")
      start = Random.new.rand(pem.length - length)
      keygap = pem[start..(start + length - 1)]
    end
    [pem.sub(keygap, '*' * length), keygap]
  end

  def merge(pem, keygap)
    Zold::Key.new(text: pem.sub('*' * keygap.length, keygap))
  end
end
