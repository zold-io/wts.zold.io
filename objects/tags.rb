# SPDX-FileCopyrightText: Copyright (c) 2018-2025 Zerocracy
# SPDX-License-Identifier: MIT

require 'zold/log'
require_relative 'wts'
require_relative 'user_error'

#
# Tags of a user.
#
class WTS::Tags
  def initialize(login, pgsql, log: Zold::Log::NULL)
    @login = login
    @pgsql = pgsql
    @log = log
  end

  # This tag exists?
  def exists?(tag)
    !@pgsql.exec('SELECT * FROM tag WHERE login = $1 and name = $2', [@login, tag]).empty?
  end

  # Add tag.
  def attach(tag)
    raise WTS::UserError, "E181: Invalid tag #{tag.inspect}" unless /^[a-z0-9-]+$/.match?(tag)
    @pgsql.exec('INSERT INTO tag (login, name) VALUES ($1, $2)', [@login, tag])
  end
end
