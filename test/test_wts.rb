# Copyright (c) 2018-2024 Zerocracy
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
require 'rack/test'
require 'webmock/minitest'
require 'zold/log'
require_relative 'test__helper'
require_relative '../wts'

module Rack
  module Test
    class Session
      def default_env
        { 'REMOTE_ADDR' => '127.0.0.1', 'HTTPS' => 'on' }.merge(headers_for_env)
      end
    end
  end
end

class WTS::AppTest < Minitest::Test
  include Rack::Test::Methods

  def app
    Sinatra::Application.set(:log, t_log)
    Sinatra::Application.set(:pool, Concurrent::FixedThreadPool.new(1, max_queue: 0, fallback_policy: :caller_runs))
    Sinatra::Application
  end

  # Fake BTC
  class FakeBtc
    def initialize(addr)
      @addr = addr
    end

    def create
      { hash: @addr, pvt: 'empty' }
    end
  end

  def test_renders_pages
    WebMock.allow_net_connect!
    [
      '/version',
      '/robots.txt',
      '/',
      '/css/main.css',
      '/gl',
      '/usd_rate',
      '/terms',
      '/payables',
      '/assets',
      '/context',
      '/remotes',
      '/quick',
      '/quick?haml=pageisabsent'
    ].each do |p|
      get(p)
      assert(last_response.ok?, last_response.body)
    end
  end

  def test_not_found
    WebMock.allow_net_connect!
    ['/unknown_path', '/js/x/y/z/not-found.js', '/css/a/b/c/not-found.css'].each do |p|
      get(p)
      assert_equal(404, last_response.status, last_response.body)
      assert_equal('text/html;charset=utf-8', last_response.content_type)
    end
  end

  def test_without_redirect
    WebMock.allow_net_connect!
    get('/rate.json?noredirect=1')
    assert_equal(200, last_response.status)
  end

  def test_200_user_pages
    WebMock.allow_net_connect!
    name = 'bill'
    login(name)
    user = WTS::User.new(
      name, WTS::Item.new(name, t_pgsql, log: t_log),
      Sinatra::Application.settings.wallets, log: t_log
    )
    user.create
    keygap = user.keygap
    user.confirm(keygap)
    [
      '/home',
      '/key',
      '/pay',
      '/balance',
      '/restart',
      '/log',
      '/push',
      '/head.json',
      '/txns.json',
      '/referrals',
      '/invoice',
      '/invoice.json',
      '/api',
      "/download?keygap=#{keygap}",
      "/id_rsa?keygap=#{keygap}",
      '/callbacks',
      '/payouts',
      '/buy-sell',
      '/btc-to-zld',
      '/zld-to-btc',
      '/zld-to-paypal'
    ].each do |p|
      get(p)
      assert_equal(200, last_response.status, "#{p} fails: #{last_response.body}")
    end
  end

  def test_302_user_pages
    WebMock.allow_net_connect!
    login('nick')
    ['/pull', '/rate'].each do |p|
      get(p)
      assert_equal(302, last_response.status, "#{p} fails: #{last_response.body}")
    end
  end

  def test_api_code
    WebMock.allow_net_connect!
    login('poly')
    get('/api')
    assert_equal(200, last_response.status, last_response.body)
  end

  def test_sell_zld
    WebMock.allow_net_connect!
    name = 'jeff079'
    login(name)
    boss = WTS::User.new(
      '0crat', WTS::Item.new('0crat', t_pgsql, log: t_log),
      Sinatra::Application.settings.wallets, log: t_log
    )
    boss.create
    user = WTS::User.new(
      name, WTS::Item.new(name, t_pgsql, log: t_log),
      Sinatra::Application.settings.wallets, log: t_log
    )
    user.create
    keygap = user.keygap
    user.confirm(keygap)
    Sinatra::Application.settings.wallets.acq(user.item.id) do |w|
      w.add(
        Zold::Txn.new(
          1,
          Time.now,
          Zold::Amount.new(zld: 1.0),
          'NOPREFIX', Zold::Id.new, '-'
        )
      )
    end
    assets = WTS::Assets.new(t_pgsql, log: t_log)
    address = assets.acquire(user.login)
    assets.set(address, 10_000_000)
    get('/zld-to-btc')
    assert_equal(200, last_response.status, last_response.body)
    csrf = Nokogiri.HTML(last_response.body).xpath('//input[@name="_csrf"]/@value')
    post(
      '/do-zld-to-btc',
      form(
        amount: '1',
        btc: '1N1R2HP9JD4LvAtp7rTkpRqF19GH7PH2ZF',
        keygap: keygap,
        _csrf: csrf
      )
    )
    assert_equal(302, last_response.status, last_response.body)
  end

  def test_pay_for_pizza
    skip
    WebMock.allow_net_connect!
    keygap = login('yegor1')
    get('/pay')
    assert_equal(200, last_response.status, last_response.body)
    csrf = Nokogiri.HTML(last_response.body).xpath('//input[@name="_csrf"]/@value')
    post(
      '/do-pay',
      form(
        keygap: keygap,
        bnf: '1111222233334444',
        amount: 100,
        details: 'for pizza',
        _csrf: csrf
      )
    )
    assert_equal(302, last_response.status, last_response.body)
    job = last_response.headers['X-Zold-Job']
    get("/job?id=#{job}")
    assert_equal(200, last_response.status, last_response.body)
    get("/output?id=#{job}")
    assert_equal(200, last_response.status, last_response.body)
    get("/job.json?id=#{job}")
    assert_equal(200, last_response.status, last_response.body)
  end

  def test_migrate
    WebMock.allow_net_connect!
    keygap = login('yegor565')
    get("/do-migrate?keygap=#{keygap}")
    assert_equal(302, last_response.status, last_response.body)
  end

  def test_push
    WebMock.allow_net_connect!
    keygap = login('yegor565')
    get("/do-push?keygap=#{keygap}")
    assert_equal(302, last_response.status, last_response.body)
  end

  def test_register_callback
    WebMock.allow_net_connect!
    login('yegor565')
    get('/wait-for?prefix=abcdefgh&regexp=.*&uri=http://localhost/')
    assert_equal(200, last_response.status, last_response.body)
  end

  def test_ops_as_sandbox
    WebMock.allow_net_connect!
    header('X-Zold-WTS', '0000000000000000-b416493aefae4ca487c4739050aaec15')
    get('/id')
    assert_equal(200, last_response.status, last_response.body)
    get('/pull?noredirect=1')
    assert_equal(200, last_response.status, last_response.body)
    get('/balance')
    assert_equal(200, last_response.status, last_response.body)
    post('/do-pay?bnf=@yegor256&details=text&amount=16.0&keygap=1234567890&noredirect=1')
    assert_equal(200, last_response.status, last_response.body)
  end

  def test_create_and_render_receipt
    WebMock.allow_net_connect!
    header('X-Zold-WTS', '0000000000000000-b416493aefae4ca487c4739050aaec15')
    get('/pull?noredirect=1')
    assert_equal(200, last_response.status, last_response.body)
    get('/receipt?txn=1')
    assert_equal(200, last_response.status, last_response.body)
    hash = SecureRandom.hex[0..8].upcase
    post("/do-receipt?txn=1&usd=10&zld=5=payer=Jeff&recipient=John&details=test&hash=#{hash}")
    assert_equal(302, last_response.status, last_response.body)
    header('X-Zold-WTS', '')
    get("/rcpt/#{hash}")
    assert_equal(200, last_response.status, last_response.body)
  end

  private

  def form(params)
    params.map { |k, v| "#{k}=#{CGI.escape(v.to_s)}" }.join('&')
  end

  def login(name)
    set_cookie("glogin=#{name}|#{name}")
    get('/create')
    assert_equal(302, last_response.status, last_response.body)
    get('/keygap')
    assert_equal(200, last_response.status, last_response.body)
    keygap = last_response.body
    csrf = Nokogiri.HTML(last_response.body).xpath('//input[@name="_csrf"]/@value')
    get('/do-confirm?keygap=' + keygap + "&_csrf=#{csrf}")
    assert_equal(302, last_response.status, last_response.body)
    get('/id')
    assert_equal(200, last_response.status, last_response.body)
    keygap
  end
end
