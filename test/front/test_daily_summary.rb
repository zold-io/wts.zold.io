# SPDX-FileCopyrightText: Copyright (c) 2018-2025 Zerocracy
# SPDX-License-Identifier: MIT

require 'minitest/autorun'
require 'webmock/minitest'
require 'zold/log'
require 'sibit'
require_relative '../test__helper'
require_relative '../../front/daily_summary'
require_relative '../../objects/payables'
require_relative '../../objects/gl'
require_relative '../../objects/toggles'
require_relative '../../objects/assets'

class WTS::DailySummaryTest < Minitest::Test
  def test_builds_report
    stub_request(:get, 'https://api.github.com/repos/zold-io/zold/releases/latest').to_return(
      body: '{"tag_name": "0.0.0", "created_at": "2019-05-21T16:32:03Z"}',
      headers: { 'Content-type': 'application/json' }
    )
    stub_request(:get, 'https://api.github.com/users/zold-io/repos').to_return(
      body: '[{"full_name": "zold-io/zold"}]',
      headers: { 'Content-type': 'application/json' }
    )
    stub_request(:get, 'https://hitsofcode.com/github/zold-io/zold/json').to_return(
      body: '{"count": 123}',
      headers: { 'Content-type': 'application/json' }
    )
    stub_request(:get, 'https://api.github.com/repos/zold-io/zold').to_return(
      body: '{"stargazers_count": 123}',
      headers: { 'Content-type': 'application/json' }
    )
    md = WTS::DailySummary.new(
      ticks: Class.new do
        def latest(_id)
          123
        end
      end.new,
      pgsql: t_pgsql,
      payables: WTS::Payables.new(t_pgsql, nil, log: t_log),
      gl: WTS::Gl.new(t_pgsql),
      config: {
        'github' => {
          'client_id' => '',
          'client_secret' => ''
        }
      },
      log: t_log,
      sibit: Sibit::Fake.new,
      toggles: WTS::Toggles.new(t_pgsql),
      assets: WTS::Assets.new(t_pgsql)
    ).markdown
    assert(md.include?('Deficit: '), md)
  end

  # @todo #283:30min The test is skipped because it fails time to time.
  #  I suspect that the problem is on their side, at hitsofcode.com. We
  #  should investigate and maybe ask them to fix something.
  def test_reads_hoc
    skip
    WebMock.allow_net_connect!
    2.times do
      ['papers', 'blog.zold.io', 'zold', 'wts.zold.io', 'zold-ruby-sdk'].each do |r|
        assert(!WTS::DailySummary::HoC.new("zold-io/#{r}", log: t_log).hoc.zero?)
        assert(!WTS::DailySummary::HoC.new("zold-io/#{r}", log: t_log).commits.zero?)
      end
    end
  end
end
