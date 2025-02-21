# SPDX-FileCopyrightText: Copyright (c) 2018-2025 Zerocracy
# SPDX-License-Identifier: MIT

require 'minitest/autorun'
require 'webmock/minitest'
require_relative 'test__helper'
require_relative '../objects/jobs'
require_relative '../objects/db_log'

class WTS::DbLogTest < Minitest::Test
  def test_updates_log
    WebMock.allow_net_connect!
    jobs = WTS::Jobs.new(t_pgsql, log: t_log)
    id = jobs.start('hello')
    log = WTS::DbLog.new(t_pgsql, id)
    log.info('hello, world!')
    log.error('bye')
    assert_equal("INFO: hello, world!\nERROR: bye\n", jobs.output(id))
  end
end
