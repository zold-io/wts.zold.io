# frozen_string_literal: true

# SPDX-FileCopyrightText: Copyright (c) 2018-2026 Zerocracy
# SPDX-License-Identifier: MIT

require 'json'
require 'loog'
require 'octokit'
require 'time'
require 'zold/amount'
require 'zold/http'
require_relative '../objects/dollars'
require_relative '../objects/gl'
require_relative '../objects/payables'
require_relative '../objects/rate'
require_relative '../objects/ticks'

class WTS::DailySummary
  class WTS::DailySummary::HoC
    def initialize(repo, log: Loog::NULL)
      @repo = repo
      @log = log
    end

    def hoc
      fetch('count')
    end

    def commits
      fetch('commits')
    end

    private

    def fetch(field)
      uri = "https://hitsofcode.com/github/#{@repo}/json"
      res = Zold::Http.new(uri: uri).get(timeout: 60)
      unless res.status == 200
        @log.error("Can't retrieve #{field.inspect} at #{uri} for #{@repo} (#{res.status}): #{res.body.inspect}")
        return 0
      end
      total = JSON.parse(res.body)[field]
      @log.debug("Field #{field.inspect} found in #{@repo}: #{total}")
      total
    end
  end

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
    release = octokit.latest_release('zold-io/zold')
    [
      "Today is #{Time.now.utc.strftime('%d-%b-%Y')} and we are doing great:\n",
      "  Wallets: [#{@payables.total}](https://wts.zold.io/payables)",
      "  Active wallets: #{@pgsql.exec(
        'SELECT COUNT(*) FROM item WHERE touched > NOW() - INTERVAL \'30 DAYS\''
      )[0]['count'].to_i} (last 30 days)",
      "  Transactions: [#{@payables.txns}](https://wts.zold.io/payables)",
      "  Total emission: [#{@payables.balance}](https://wts.zold.io/payables)",
      "  Distributed: [#{Zold::Amount.new(zents: (@ticks.latest('Emission') - @ticks.latest('Office')).to_i)}](https://wts.zold.io/rate)",
      "  24-hours volume: [#{@gl.volume}](https://wts.zold.io/gl)",
      "  24-hours txns count: [#{@gl.count}](https://wts.zold.io/gl)",
      "  Bitcoin price: [#{WTS::Dollars.new(price)}](https://coinmarketcap.com/currencies/bitcoin/)",
      '  Bitcoin tx fee: ' \
      "[#{WTS::Dollars.new(@sibit.fees[:XL] * 250.0 * price / 100_000_000)}](https://bitcoinfees.info/)",
      "  ZLD price: [#{format('%.08f', rate)}](https://wts.zold.io/rate) (#{WTS::Dollars.new(price * rate)})",
      "  Coverage: [#{(100 * coverage / rate).round}%](http://papers.zold.io/fin-model.pdf) " \
      "/ [#{format('%.08f', coverage)}](https://wts.zold.io/rate)",
      "  The fund: [#{@assets.balance.round(4)} BTC](https://wts.zold.io/rate) " \
      "(#{WTS::Dollars.new(price * @assets.balance)})",
      "  Deficit: [#{(@ticks.latest('Deficit') / 100_000_000).round(2)} BTC](https://wts.zold.io/rate)",
      '',
      "  Zold: [#{release[:tag_name]}](https://github.com/zold-io/zold/releases/tag/#{release[:tag_name]}) " \
      "/ #{((Time.now - release[:created_at]) / (24 * 60 * 60)).round} days ago",
      "  Nodes: [#{@ticks.latest('Nodes').round}](https://wts.zold.io/remotes)",
      '  [HoC](https://www.yegor256.com/2014/11/14/hits-of-code.html)/cmts ' \
      "in #{repositories.count}: #{(hoc / 1000).round}K / #{commits}",
      "  [GitHub](https://github.com/zold-io) stars/forks: #{stars} / #{forks}",
      "  Open GitHub issues: #{issues}",
      "\nThanks for keeping an eye on us!"
    ].join("\n")
  end

  def octokit
    Octokit::Client.new(login: @config['github']['client_id'], password: @config['github']['client_secret'])
  end

  def repositories
    octokit.repositories('zold-io').map { |json| json['full_name'] }
  end

  def hoc
    repositories.sum { |r| HoC.new(r, log: @log).hoc.to_i }
  end

  def commits
    repositories.sum { |r| HoC.new(r, log: @log).commits.to_i }
  end

  def stars
    repositories.sum do |r|
      octokit.repository(r)['stargazers_count'].to_i
    end
  end

  def issues
    repositories.sum do |r|
      octokit.repository(r)['open_issues_count'].to_i
    end
  end

  def forks
    repositories.sum do |r|
      octokit.repository(r)['forks_count'].to_i
    end
  end
end
