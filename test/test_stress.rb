# Copyright (c) 2018 Yegor Bugayenko
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

require 'minitest/autorun'
require 'zold/key'
require 'zold/id'
require 'zold/log'
require 'zold/http'
require 'zold/score'
require 'zold/wallets'
require 'zold/remotes'
require 'zold/commands/create'
require 'zold/commands/pay'
require 'zold/commands/push'
require 'zold/commands/node'
require 'tmpdir'
require 'random-port'
require_relative 'test__helper'
require_relative '../objects/stress'

class StressTest < Minitest::Test
  def test_runs_a_few_full_cycles
    exec do |stress|
      thread = stress.start(delay: 0, cycles: 5)
      thread.join
      json = stress.to_json
      assert_equal(35, json['paid'][:total])
      assert(json['arrived'][:total] > 30)
      assert_equal(5, json['cycles_ok'][:total])
    end
  end

  def test_renders_json
    exec do |stress|
      json = stress.to_json
      assert(json[:wallets])
      assert(json[:thread])
      assert(json[:waiting])
      assert(json[:alive_hours])
    end
  end

  private

  def exec
    RandomPort::Pool::SINGLETON.acquire do |port|
      Dir.mktmpdir do |dir|
        thread = Thread.new do
          Zold::VerboseThread.new(test_log).run do
            home = File.join(dir, 'server')
            FileUtils.mkdir_p(home)
            node = Zold::Node.new(
              wallets: Zold::Wallets.new(home),
              remotes: Zold::Remotes.new(file: File.join(home, 'remotes')),
              copies: File.join(home, 'copies'),
              log: test_log
            )
            node.run(
              [
                '--home', home,
                '--network=test',
                '--port', port.to_s,
                '--host=localhost',
                '--bind-port', port.to_s,
                '--threads=1',
                '--standalone',
                '--no-metronome',
                '--dump-errors',
                '--halt-code=test',
                '--strength=2',
                '--routine-immediately',
                '--invoice=NOPREFIX@ffffffffffffffff'
              ]
            )
          end
        end
        loop do
          break if Zold::Http.new(uri: "http://localhost:#{port}/", score: Zold::Score::ZERO).get.code == '200'
          test_log.debug('Waiting for the node to start...')
        end
        wallets = Zold::Wallets.new(dir)
        remotes = Zold::Remotes.new(file: File.join(dir, 'remotes'), network: 'test')
        remotes.clean
        remotes.add('localhost', port)
        Zold::Create.new(wallets: wallets, log: test_log).run(
          ['create', '--public-key=test-assets/id_rsa.pub', '0000000000000000', '--network=test']
        )
        id = Zold::Create.new(wallets: wallets, log: test_log).run(
          ['create', '--public-key=test-assets/id_rsa.pub', '--network=test']
        )
        Zold::Pay.new(wallets: wallets, remotes: remotes, log: test_log).run(
          ['pay', '0000000000000000', id.to_s, '1.00', 'start', '--private-key=test-assets/id_rsa']
        )
        Zold::Push.new(wallets: wallets, remotes: remotes, log: test_log).run(
          ['push', '0000000000000000', id.to_s, '--ignore-score-weakness']
        )
        stress = Stress.new(
          id: id,
          pub: Zold::Key.new(file: 'test-assets/id_rsa.pub'),
          pvt: Zold::Key.new(file: 'test-assets/id_rsa'),
          wallets: wallets,
          remotes: remotes,
          copies: File.join(dir, 'copies'),
          log: test_log
        )
        begin
          yield stress
        ensure
          Zold::Http.new(uri: "http://localhost:#{port}/?halt=test", score: Zold::Score::ZERO).get
          thread.join
        end
      end
    end
  end
end
