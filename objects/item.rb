# frozen_string_literal: true

# SPDX-FileCopyrightText: Copyright (c) 2018-2026 Zerocracy
# SPDX-License-Identifier: MIT

require 'loog'
require 'zold/id'
require 'zold/key'
require_relative 'keygap'
require_relative 'tags'
require_relative 'user_error'
require_relative 'wts'

class WTS::Item
  attr_reader :login

  def initialize(login, pgsql, log: Loog::NULL)
    @login = login.downcase
    @pgsql = pgsql
    @log = log
  end

  def tags
    WTS::Tags.new(@login, @pgsql, log: @log)
  end

  def exists?
    !@pgsql.exec('SELECT * FROM item WHERE login = $1', [login]).empty?
  end

  def create(id, key, length: 16)
    pem, keygap = WTS::Keygap.new.extract(key.to_s, length)
    @pgsql.transaction do |t|
      t.exec(
        [
          'INSERT INTO item (login, id, pem) VALUES ($1, $2, $3)',
          'ON CONFLICT (login) DO UPDATE SET id = $2, pem = $3'
        ].join(' '),
        [@login, id.to_s, pem]
      )
      t.exec(
        [
          'INSERT INTO keygap (login, keygap) VALUES ($1, $2)',
          'ON CONFLICT (login) DO UPDATE SET keygap = $2'
        ].join(' '),
        [@login, keygap]
      )
    end
    @log.info("New user #{@login} created, wallet ID is #{id}, keygap is '#{keygap[0, 2]}#{'.' * (keygap.length - 2)}'")
    keygap
  end

  def replace_id(id)
    @pgsql.exec('UPDATE item SET id = $1 WHERE login = $2', [id, @login])
  end

  def key(keygap)
    key = WTS::Keygap.new.merge(pem, keygap)
    @log.debug("The private key of #{@login} reassembled: #{key.to_s.length} chars")
    key
  end

  def pem
    @pgsql.exec('SELECT pem FROM item WHERE login = $1', [@login])[0]['pem']
  end

  def id
    row = @pgsql.exec('SELECT id FROM item WHERE login = $1', [@login])[0]
    raise(RuntimeError, "User #{@login} is not yet registered") if row.nil?
    Zold::Id.new(row['id'])
  end

  def keygap
    row = @pgsql.exec('SELECT keygap FROM keygap WHERE login = $1', [@login])[0]
    raise(RuntimeError, "The user #{@login} doesn't have a keygap anymore") if row.nil?
    @log.debug("The keygap of #{@login} retrieved")
    row['keygap']
  end

  def wiped?
    @pgsql.exec('SELECT keygap FROM keygap WHERE login = $1', [@login]).empty?
  end

  def wipe(keygap)
    before = keygap
    if keygap != before
      raise(RuntimeError, "Keygap '#{keygap}' of #{@login} doesn't match '#{before[0, 2]}#{'.' * (before.length - 2)}'")
    end
    @pgsql.exec('DELETE FROM keygap WHERE login = $1', [@login])
    @log.debug("The keygap of #{@login} was destroyed")
  end

  def touch
    @pgsql.exec('UPDATE item SET touched = NOW() WHERE login = $1', [@login])
  end

  def rename(to)
    @pgsql.exec('UPDATE item SET login = $1 WHERE login = $2', [to, @login])
    @login = to
  end
end
