# frozen_string_literal: true

# SPDX-FileCopyrightText: Copyright (c) 2018-2026 Zerocracy
# SPDX-License-Identifier: MIT

$stdout.sync = true

ENV['RACK_ENV'] = 'test'

require 'simplecov'
require 'simplecov-cobertura'
unless SimpleCov.running || ENV['PICKS']
  SimpleCov.command_name('test')
  SimpleCov.formatter = SimpleCov::Formatter::MultiFormatter.new(
    [
      SimpleCov::Formatter::HTMLFormatter,
      SimpleCov::Formatter::CoberturaFormatter
    ]
  )
  SimpleCov.minimum_coverage(85)
  SimpleCov.minimum_coverage_by_file(50)
  SimpleCov.start do
    add_filter 'test/'
    add_filter 'vendor/'
    add_filter 'target/'
    track_files 'lib/**/*.rb'
    track_files '*.rb'
  end
end

require 'zold/hands'
Zold::Hands.start

require 'minitest/autorun'
require 'minitest/reporters'
require 'rack/test'
require 'webmock/minitest'
Minitest::Reporters.use!([Minitest::Reporters::SpecReporter.new])
Minitest.load(:minitest_reporter)

require 'pgtk/pool'
require 'yaml'
module Minitest
  class Test
    def t_log
      require('loog')
      @t_log ||= ENV['TEST_QUIET_LOG'] == 'true' ? Loog::NULL : Loog::VERBOSE
    end

    def t_pgsql
      @@t_pgsql ||=
        begin
          x = Pgtk::Pool.new(Pgtk::Wire::Yaml.new(File.join(__dir__, '../target/pgsql-config.yml')), log: t_log)
          x.start!
          x
        end
      # rubocop:enable Style/ClassVars
    end
  end
end
