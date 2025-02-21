# SPDX-FileCopyrightText: Copyright (c) 2018-2025 Zerocracy
# SPDX-License-Identifier: MIT

require 'raven'
require 'backtrace'
require 'zold/log'
require_relative 'wts'
require_relative 'user_error'

#
# Daemons.
#
class WTS::Daemons
  def initialize(pgsql, log: Zold::Log::NULL)
    @pgsql = pgsql
    @log = log
    @threads = {}
  end

  def start(id, seconds = 60, pause: 5)
    @threads[id] = Thread.new do
      sleep(pause) # to let the main script load all Ruby methods
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
      rescue Exception
        # If we reach this point, we must not even try to
        # do anything. Here we must quietly ignore everything
        # and let the daemon go to the next cycle.
      end
    end
  end

  private

  # The age of the daemon in seconds, or zero if not yet found
  def age(id)
    row = @pgsql.exec('SELECT executed FROM daemon WHERE id = $1', [id])[0]
    return 10_000_000_000 if row.nil?
    Time.now - Time.parse(row['executed'])
  end
end
