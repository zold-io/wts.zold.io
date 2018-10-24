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
require 'zold/sync_wallets'
require 'zold/cached_wallets'
require 'zold/remotes'
require 'zold/commands/create'
require 'zold/commands/pay'
require 'zold/commands/push'
require 'zold/commands/node'
require 'tmpdir'
require_relative 'test__helper'
require_relative 'fake_node'
require_relative '../objects/stress'

class StressTest < Minitest::Test
  def test_runs_a_few_full_cycles
    skip
    exec do |stress|
      stress.run(delay: 0, cycles: 5, opts: ['--ignore-score-weakness', '--network=test'])
      json = stress.to_json
      assert(json['arrived'][:total] > 30)
      assert_equal(5, json['cycle_ok'][:total])
    end
  end

  def test_renders_json
    exec do |stress|
      json = stress.to_json
      assert(json[:wallets])
      assert(json[:thread])
      assert(json[:air])
    end
  end

  private

  def exec
    FakeNode.new(Zold::Log::Quiet.new).exec do |port|
      Dir.mktmpdir do |dir|
        wallets = Zold::CachedWallets.new(Zold::SyncWallets.new(Zold::Wallets.new(dir)))
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
        yield Stress.new(
          id: id,
          pub: Zold::Key.new(file: 'test-assets/id_rsa.pub'),
          pvt: Zold::Key.new(file: 'test-assets/id_rsa'),
          wallets: wallets,
          remotes: remotes,
          copies: File.join(dir, 'copies'),
          log: Zold::Log::Sync.new(Zold::Log::Regular.new)
        )
      end
    end
  end
end
