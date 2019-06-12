# Copyright (c) 2016-2019 Yegor Bugayenko
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the 'Software'), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED 'AS IS', WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

STDOUT.sync = true

ENV['RACK_ENV'] = 'test'

require 'simplecov'
SimpleCov.start
if ENV['CI'] == 'true'
  require 'codecov'
  SimpleCov.formatter = SimpleCov::Formatter::Codecov
end

require 'zold/hands'
Zold::Hands.start

require 'yaml'
require 'minitest/autorun'
require 'pgtk/pool'
module Minitest
  class Test
    def test_log
      require 'zold/log'
      @test_log ||= ENV['TEST_QUIET_LOG'] ? Zold::Log::NULL : Zold::Log::VERBOSE
    end

    def test_pgsql
      config = YAML.load_file('target/pgsql-config.yml')
      # rubocop:disable Style/ClassVars
      @@test_pgsql ||= Pgtk::Pool.new(
        host: config['pgsql']['host'],
        port: config['pgsql']['port'].to_i,
        dbname: config['pgsql']['dbname'],
        user: config['pgsql']['user'],
        password: config['pgsql']['password'],
        log: test_log
      ).start
      # rubocop:enable Style/ClassVars
    end
  end
end
