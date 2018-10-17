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
require 'zold/wallets'
require 'zold/sync_wallets'
require 'zold/remotes'
require 'zold/commands/create'
require 'tmpdir'
require_relative 'test__helper'
require_relative 'fake_node'
require_relative '../objects/pmnts'
require_relative '../objects/stats'

class PmntsTest < Minitest::Test
  def test_pays_one_on_one
    Dir.mktmpdir do |home|
      wallets = Zold::SyncWallets.new(Zold::Wallets.new(home))
      remotes = Zold::Remotes.new(file: File.join(home, 'remotes'), network: 'test')
      Zold::Create.new(wallets: wallets, log: test_log).run(
        ['create', '--public-key=test-assets/id_rsa.pub', Zold::Id::ROOT.to_s, '--network=test']
      )
      id = Zold::Create.new(wallets: wallets, log: test_log).run(
        ['create', '--public-key=test-assets/id_rsa.pub', '--network=test']
      )
      Zold::Pay.new(wallets: wallets, remotes: remotes, log: test_log).run(
        ['pay', Zold::Id::ROOT.to_s, id.to_s, '7.00', 'start', '--private-key=test-assets/id_rsa']
      )
      sent = Pmnts.new(
        pvt: Zold::Key.new(file: 'test-assets/id_rsa'),
        wallets: wallets,
        remotes: remotes,
        stats: Stats.new(log: test_log),
        log: test_log
      ).send
      assert_equal(1, sent.count)
      assert_equal(id, sent[0][:source])
      assert_equal(Zold::Id::ROOT, sent[0][:target])
      assert_equal(Zold::Amount.new(zld: 3.5), wallets.find(id, &:balance))
      assert_equal(Zold::Amount.new(zld: -3.5), wallets.find(Zold::Id::ROOT, &:balance))
    end
  end

  def test_pays
    Dir.mktmpdir do |home|
      wallets = Zold::Wallets.new(home)
      remotes = Zold::Remotes.new(file: File.join(home, 'remotes'), network: 'test')
      Zold::Create.new(wallets: wallets, log: test_log).run(
        ['create', '--public-key=test-assets/id_rsa.pub', Zold::Id::ROOT.to_s, '--network=test']
      )
      total = 6
      ids = []
      total.times do
        id = Zold::Create.new(wallets: wallets, log: test_log).run(
          ['create', '--public-key=test-assets/id_rsa.pub', '--network=test']
        )
        Zold::Pay.new(wallets: wallets, remotes: remotes, log: test_log).run(
          ['pay', Zold::Id::ROOT.to_s, id.to_s, '7.00', 'start', '--private-key=test-assets/id_rsa']
        )
        ids << id
      end
      sent = Pmnts.new(
        pvt: Zold::Key.new(file: 'test-assets/id_rsa'),
        wallets: wallets,
        remotes: remotes,
        stats: Stats.new(log: test_log),
        log: test_log
      ).send
      assert_equal(total * total, sent.count)
      assert_equal(ids.sort, sent.map { |s| s[:source] }.sort.uniq)
    end
  end
end
