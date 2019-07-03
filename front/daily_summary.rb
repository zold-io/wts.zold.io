# Copyright (c) 2018-2019 Zerocracy, Inc.
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

require 'time'
require 'json'
require 'octokit'
require 'zold/amount'
require 'zold/http'
require_relative '../objects/ticks'
require_relative '../objects/gl'
require_relative '../objects/payables'
require_relative '../objects/dollars'
require_relative '../objects/rate'

# Daily summary.
# Author:: Yegor Bugayenko (yegor256@gmail.com)
# Copyright:: Copyright (c) 2018 Yegor Bugayenko
# License:: MIT
class WTS::DailySummary
  def initialize(ticks:, pgsql:, payables:, gl:, config:, log:, sibit:, toggles:, assets:)
    @ticks = ticks
    @pgsql = pgsql
    @payables = payables
    @gl = gl
    @config = config
    @log = log
    @sibit = sibit
    @toggles = toggles
    @assets = assets
  end

  def markdown
    price = @sibit.price
    rate = WTS::Rate.new(@toggles).to_f
    coverage = @ticks.latest('Coverage') / 100_000_000
    deficit = @ticks.latest('Deficit') / 100_000_000
    distributed = Zold::Amount.new(
      zents: (@ticks.latest('Emission') - @ticks.latest('Office')).to_i
    )
    active = @pgsql.exec(
      'SELECT COUNT(*) FROM item WHERE touched > NOW() - INTERVAL \'30 DAYS\''
    )[0]['count'].to_i
    release = octokit.latest_release('zold-io/zold')
    [
      "Today is #{Time.now.utc.strftime('%d-%b-%Y')} and we are doing great:\n",
      "  Wallets: [#{@payables.total}](https://wts.zold.io/payables)",
      "  Active wallets: #{active} (last 30 days)",
      "  Transactions: [#{@payables.txns}](https://wts.zold.io/payables)",
      "  Total emission: [#{@payables.balance}](https://wts.zold.io/payables)",
      "  Distributed: [#{distributed}](https://wts.zold.io/rate)",
      "  24-hours volume: [#{@gl.volume}](https://wts.zold.io/gl)",
      "  24-hours txns count: [#{@gl.count}](https://wts.zold.io/gl)",
      "  Bitcoin price: [#{WTS::Dollars.new(price)}](https://coinmarketcap.com/currencies/bitcoin/)",
      "  Bitcoin tx fee: \
[#{WTS::Dollars.new(@sibit.fees[:XL] * 250.0 * price / 100_000_000)}](https://bitcoinfees.info/)",
      "  ZLD price: [#{format('%.08f', rate)}](https://wts.zold.io/rate) (#{WTS::Dollars.new(price * rate)})",
      "  Coverage: [#{(100 * coverage / rate).round}%](http://papers.zold.io/fin-model.pdf) \
/ [#{format('%.08f', coverage)}](https://wts.zold.io/rate)",
      "  The fund: [#{@assets.balance.round(4)} BTC](https://wts.zold.io/rate) \
(#{WTS::Dollars.new(price * @assets.balance)})",
      "  Deficit: [#{deficit.round(2)} BTC](https://wts.zold.io/rate)",
      '',
      "  Zold version: [#{release[:tag_name]}](https://github.com/zold-io/zold/releases/tag/#{release[:tag_name]}) \
/ #{((Time.now - release[:created_at]) / (24 * 60 * 60)).round} days ago",
      "  Nodes: [#{@ticks.latest('Nodes').round}](https://wts.zold.io/remotes)",
      "  [HoC](https://www.yegor256.com/2014/11/14/hits-of-code.html) \
in #{repositories.count} repos: #{(hoc / 1000).round}K",
      "  [GitHub](https://github.com/zold-io) stars/forks: #{stars} / #{forks}",
      "\nThanks for keeping an eye on us!"
    ].join("\n")
  end

  def octokit
    Octokit::Client.new(
      login: @config['github']['client_id'],
      password: @config['github']['client_secret']
    )
  end

  # Names of all our repos.
  def repositories
    octokit.repositories('zold-io').map { |json| json['full_name'] }
  end

  # Total amount of hits-of-code in all Zold repositories
  def hoc
    repositories.map do |r|
      uri = "https://hitsofcode.com/github/#{r}/json"
      res = Zold::Http.new(uri: uri).get(timeout: 32)
      unless res.status == 200
        @log.error("Can't retrieve HoC at #{uri} for #{r} (#{res.status}): #{res.body.inspect}")
        return 0
      end
      JSON.parse(res.body)['count']
    end.inject(&:+)
  end

  # Total amount of GitHub stars.
  def stars
    repositories.map do |r|
      octokit.repository(r)['stargazers_count']
    end.inject(&:+)
  end

  # Total amount of GitHub forks.
  def forks
    repositories.map do |r|
      octokit.repository(r)['forks_count']
    end.inject(&:+)
  end
end
