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
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

require 'zold/log'
require 'zold/id'
require 'zold/key'
require 'zold/amount'
require 'zold/commands/create'
require 'zold/commands/pull'
require 'zold/commands/remove'
require_relative 'stats'

#
# The pool of wallets.
#
class Pool
  def initialize(id:, pub:, wallets:, remotes:, copies:, stats:, log: Zold::Log::Quiet.new)
    raise 'Wallet ID can\'t be nil' if id.nil?
    raise 'Wallet ID must be of type Id' unless id.is_a?(Zold::Id)
    @id = id
    raise 'Public RSA key can\'t be nil' if pub.nil?
    raise 'Public RSA key must be of type Key' unless pub.is_a?(Zold::Key)
    @pub = pub
    raise 'Wallets can\'t be nil' if wallets.nil?
    @wallets = wallets
    raise 'Remotes can\'t be nil' if remotes.nil?
    @remotes = remotes
    raise 'Copies can\'t be nil' if copies.nil?
    @copies = copies
    raise 'Log can\'t be nil' if log.nil?
    @log = log
    @stats = stats
  end

  def rebuild(size, opts = [])
    start = Time.now
    candidates = [@id]
    @wallets.all.each do |id|
      @wallets.find(id, &:txns).each do |t|
        next unless t.amount.negative?
        candidates << t.bnf
      end
    end
    candidates.uniq.shuffle.each do |id|
      @wallets.all.each do |w|
        next if @wallets.find(w, &:balance) > Zold::Amount.new(zld: 0.01)
        Zold::Remove.new(wallets: @wallets, log: @log).run(
          ['remove', w.to_s]
        )
      end
      break if @wallets.all.count > size
      @stats.exec('pull') do
        Zold::Pull.new(wallets: @wallets, remotes: @remotes, copies: @copies, log: @log).run(
          ['pull', id.to_s] + opts
        )
      end
    end
    Tempfile.open do |f|
      File.write(f, @pub.to_s)
      while @wallets.all.count < size
        Zold::Create.new(wallets: @wallets, log: @log).run(
          ['create', "--public-key=#{f.path}"]
        )
      end
    end
  end

  def repull(opts = [])
    @wallets.all.each do |id|
      Zold::Remove.new(wallets: @wallets, log: @log).run(
        ['remove', id.to_s]
      )
      @stats.exec('pull') do
        Zold::Pull.new(wallets: @wallets, remotes: @remotes, copies: @copies, log: @log).run(
          ['pull', id.to_s] + opts
        )
      end
    end
  end
end
