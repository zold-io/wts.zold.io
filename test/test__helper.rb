# SPDX-FileCopyrightText: Copyright (c) 2018-2025 Zerocracy
# SPDX-License-Identifier: MIT

$stdout.sync = true

ENV['RACK_ENV'] = 'test'

require 'simplecov'
SimpleCov.start

require 'zold/hands'
Zold::Hands.start

require 'minitest/reporters'
Minitest::Reporters.use! [Minitest::Reporters::SpecReporter.new]

require 'yaml'
require 'minitest/autorun'
require 'pgtk/pool'
module Minitest
  class Test
    def t_log
      require 'zold/log'
      @t_log ||= ENV['TEST_QUIET_LOG'] ? Zold::Log::NULL : Zold::Log::VERBOSE
    end

    def t_pgsql
      # rubocop:disable Style/ClassVars
      @@t_pgsql ||= Pgtk::Pool.new(
        Pgtk::Wire::Yaml.new(File.join(__dir__, '../target/pgsql-config.yml')),
        log: t_log
      ).start
      # rubocop:enable Style/ClassVars
    end
  end
end
