# SPDX-FileCopyrightText: Copyright (c) 2018-2025 Zerocracy
# SPDX-License-Identifier: MIT

#
# Tee log.
#
class WTS::TeeLog
  def initialize(first, second)
    @first = first
    @second = second
  end

  def content
    @second.content
  end

  def debug(msg)
    @first.debug(msg)
    @second.debug(msg)
  end

  def debug?
    @first.debug? || @second.debug?
  end

  def info(msg)
    @first.info(msg)
    @second.info(msg)
  end

  def info?
    @first.info? || @second.info?
  end

  def error(msg)
    @first.error(msg)
    @second.error(msg)
  end
end
