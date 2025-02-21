# SPDX-FileCopyrightText: Copyright (c) 2018-2025 Zerocracy
# SPDX-License-Identifier: MIT

require 'zold/key'

#
# Keygap code.
#
class WTS::Keygap
  # Extracts a random keygap and returns an array of [pem, keygap]
  def extract(key, length = 16)
    pem = key.to_s
    keygap = ''
    until keygap =~ /^[a-zA-Z0-9]+$/ && !keygap.include?("\n")
      start = Random.new.rand(pem.length - length)
      keygap = pem[start..(start + length - 1)]
    end
    [pem.sub(keygap, '*' * length), keygap]
  end

  # Returns Zold::Key
  def merge(pem, keygap)
    Zold::Key.new(text: pem.sub('*' * keygap.length, keygap))
  end
end
