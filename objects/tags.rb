# frozen_string_literal: true

# SPDX-FileCopyrightText: Copyright (c) 2018-2026 Zerocracy
# SPDX-License-Identifier: MIT

require 'loog'
require_relative 'user_error'
require_relative 'wts'

class WTS::Tags
  def initialize(login, pgsql, log: Loog::NULL)
    @login = login
    @pgsql = pgsql
    @log = log
  end

  def exists?(tag)
    !@pgsql.exec('SELECT * FROM tag WHERE login = $1 and name = $2', [@login, tag]).empty?
  end

  def attach(tag)
    raise(WTS::UserError, "E181: Invalid tag #{tag.inspect}") unless /^[a-z0-9-]+$/.match?(tag)
    @pgsql.exec('INSERT INTO tag (login, name) VALUES ($1, $2)', [@login, tag])
  end
end
