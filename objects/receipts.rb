# SPDX-FileCopyrightText: Copyright (c) 2018-2025 Zerocracy
# SPDX-License-Identifier: MIT

require 'zold/log'
require_relative 'user_error'

# Receipts.
# Author:: Yegor Bugayenko (yegor256@gmail.com)
# Copyright:: Copyright (c) 2018 Yegor Bugayenko
# License:: MIT
class WTS::Receipts
  def initialize(pgsql, log: Zold::Log::NULL)
    @pgsql = pgsql
    @log = log
  end

  # Create new one
  def create(login, hash, details)
    id = @pgsql.exec(
      'INSERT INTO receipt (login, hash, details) VALUES ($1, $2, $3) RETURNING id',
      [login, hash, details]
    )[0]['id'].to_i
    @log.debug("New receipt #{id} generated")
    id
  end

  def details(hash)
    row = @pgsql.exec('SELECT details FROM receipt WHERE hash=$1', [hash])[0]
    raise WTS::UserError, "E225: Receipt not found by hash #{hash.inspect}" if row.nil?
    row['details']
  end
end
