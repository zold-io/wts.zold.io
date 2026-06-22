# frozen_string_literal: true

# SPDX-FileCopyrightText: Copyright (c) 2018-2026 Zerocracy
# SPDX-License-Identifier: MIT

require 'backtrace'
require 'loog'
require 'raven'
require_relative 'user_error'
require_relative 'wts'

class WTS::Daemons
  def initialize(pgsql, log: Loog::NULL)
    @pgsql = pgsql
    @log = log
    @threads = {}
  end

  def start(id, seconds = 60, pause: 5)
    @threads[id] =
      Thread.new do
        sleep(pause)
        loop do
          sleep((seconds - age(id)).clamp(0, 5 * 60))
          next if age(id) < seconds
          begin
            yield
          rescue WTS::UserError => e
            @log.error(Backtrace.new(e))
          rescue Exception => e
            Raven.capture_exception(e)
            @log.error(Backtrace.new(e))
          end
          @pgsql.exec('INSERT INTO daemon (id) VALUES ($1) ON CONFLICT (id) DO UPDATE SET executed = NOW()', [id])
        rescue Exception => e
          @log.error(Backtrace.new(e))
        end
      end
  end

  private

  def age(id)
    row = @pgsql.exec('SELECT executed FROM daemon WHERE id = $1', [id])[0]
    return 10_000_000_000 if row.nil?
    Time.now - Time.parse(row['executed'])
  end
end
