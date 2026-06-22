# frozen_string_literal: true

# SPDX-FileCopyrightText: Copyright (c) 2018-2026 Zerocracy
# SPDX-License-Identifier: MIT

require 'loog'
require 'securerandom'
require_relative 'user_error'
require_relative 'wts'

class WTS::Jobs
  def initialize(pgsql, log: Loog::NULL)
    @pgsql = pgsql
    @log = log
  end

  def count
    @pgsql.exec('SELECT COUNT(*) FROM job')[0]['count'].to_i
  end

  def fetch(offset: 0, limit: 25)
    @pgsql.exec('SELECT * FROM job ORDER BY started DESC OFFSET $1 LIMIT $2', [offset, limit]).map do |r|
      {
        id: r['id'],
        log: r['log'],
        started: Time.parse(r['started'])
      }
    end
  end

  def exists?(id)
    !@pgsql.exec('SELECT * FROM job WHERE id = $1', [id]).empty?
  end

  def gc(minutes = 60)
    @pgsql.transaction do |t|
      t.exec(
        "UPDATE job SET log = $1 WHERE started < NOW() - INTERVAL '#{minutes} MINUTES' AND log = 'Running'",
        [
          [
            "We are sorry, but most probably the job is lost at #{Time.now.utc.iso8601},",
            "since we don't see any output from it for more than #{minutes} minutes; try again..."
          ].join(' ')
        ]
      )
      t.exec("DELETE FROM job WHERE started < NOW() - INTERVAL '180 DAYS'")
    end
  end

  def start(login)
    uuid = SecureRandom.uuid
    @pgsql.exec('INSERT INTO job (id, log, login) VALUES ($1, $2, $3)', [uuid, 'Running', login])
    uuid
  end

  def status(id)
    status = read(id)
    status = 'Error' if status != 'OK' && status != 'Running'
    status
  end

  def read(id)
    rows = @pgsql.exec('SELECT log FROM job WHERE id = $1', [id])
    raise(WTS::UserError, "EJob #{id} not found") if rows.empty?
    rows[0]['log']
  end

  def update(id, log)
    @pgsql.exec('UPDATE job SET log = $2 WHERE id = $1', [id, log])
  end

  def result(id, key, value)
    @pgsql.exec(
      'INSERT INTO result (job, key, value) VALUES ($1, $2, $3) ON CONFLICT (job, key) DO UPDATE SET value = $3',
      [id, key, value]
    )
  end

  def results(id)
    @pgsql.exec('SELECT key, value FROM result WHERE job = $1', [id]).to_h do |r|
      [r['key'], r['value']]
    end
  end

  def output(id)
    rows = @pgsql.exec('SELECT output FROM job WHERE id = $1', [id])
    raise(WTS::UserError, "EJob #{id} not found") if rows.empty?
    rows[0]['output']
  end
end
