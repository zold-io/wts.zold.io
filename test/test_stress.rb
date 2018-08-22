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
require 'zold/remotes'
require 'tmpdir'
require_relative 'test__helper'
require_relative '../objects/stress'

class StressTest < Minitest::Test
  def test_pulls_wallets
    Dir.mktmpdir do |dir|
      wallets = Zold::Wallets.new(dir)
      remotes = Zold::Remotes.new(file: File.join(dir, 'remotes'), network: 'zold')
      stress = Stress.new(
        id: Zold::Id.new('221255bc9af7baec'),
        pub: Zold::Key.new(text: ''),
        pvt: Zold::Key.new(text: ''),
        wallets: wallets,
        remotes: remotes,
        copies: File.join(dir, 'copies'),
        log: Zold::Log::Regular.new
      )
      stress.reload
    end
  end
end
