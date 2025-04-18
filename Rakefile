# SPDX-FileCopyrightText: Copyright (c) 2018-2025 Zerocracy
# SPDX-License-Identifier: MIT

$stdout.sync = true

require 'date'
require 'English'
require 'rake'
require 'rake/clean'
require 'rdoc'
require 'rubygems'
require 'shellwords'
require 'yaml'

ENV['RACK_ENV'] = 'test'

task default: %i[clean test rubocop xcop eslint copyright]

require 'rake/testtask'
Rake::TestTask.new(test: %i[pgsql liquibase]) do |test|
  Rake::Cleaner.cleanup_files(['coverage'])
  ENV['TEST_QUIET_LOG'] = 'true' if ARGV.include?('--quiet')
  test.libs << 'lib' << 'test'
  test.pattern = 'test/**/test_*.rb'
  test.verbose = true
  test.warning = false
end

require 'rubocop/rake_task'
RuboCop::RakeTask.new(:rubocop) do |task|
  task.fail_on_error = true
  task.requires << 'rubocop-rspec'
end

require 'eslintrb/eslinttask'
Eslintrb::EslintTask.new(:eslint) do |t|
  t.pattern = 'assets/js/**/*.js'
  t.options = :defaults
end

require 'xcop/rake_task'
Xcop::RakeTask.new(:xcop) do |task|
  task.license = 'LICENSE.txt'
  task.includes = ['**/*.xml', '**/*.xsl', '**/*.xsd', '**/*.html']
  task.excludes = ['target/**/*', 'coverage/**/*']
end

require 'pgtk/pgsql_task'
Pgtk::PgsqlTask.new(:pgsql) do |t|
  t.dir = 'target/pgsql'
  t.fresh_start = true
  t.user = 'test'
  t.password = 'test'
  t.dbname = 'test'
  t.yaml = 'target/pgsql-config.yml'
end

require 'pgtk/liquibase_task'
Pgtk::LiquibaseTask.new(:liquibase) do |t|
  t.master = 'liquibase/master.xml'
  t.yaml = ['target/pgsql-config.yml', 'config.yml']
end

task(run: %i[pgsql liquibase]) do
  puts 'Starting the app...'
  system('rerun -b "RACK_ENV=test ruby wts.rb"')
end

task(:copyright) do
  sh "grep -q -r '2018-#{Date.today.strftime('%Y')}' \
    --include '*.rb' \
    --include '*.txt' \
    --include 'Rakefile' \
    ."
end
