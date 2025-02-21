# SPDX-FileCopyrightText: Copyright (c) 2018-2025 Zerocracy
# SPDX-License-Identifier: MIT

#
# Log that writes to Pgsql.
#
class WTS::DbLog
  def initialize(pgsql, jid)
    @pgsql = pgsql
    @jid = jid
  end

  def debug(msg)
    update('DEBUG', msg)
  end

  def debug?
    true
  end

  def info(msg)
    update('INFO', msg)
  end

  def info?
    true
  end

  def error(msg)
    update('ERROR', msg)
  end

  private

  def update(level, msg)
    @pgsql.exec(
      'UPDATE job SET output = output || $1 WHERE id = $2',
      ["#{level}: #{msg}\n", @jid]
    )
  end
end
