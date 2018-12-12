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
require 'webmock/minitest'
require 'rack/test'
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

class AppTest < Minitest::Test
  include Rack::Test::Methods

  def app
    Sinatra::Application.set(:log, Zold::Log::VERBOSE)
    Sinatra::Application.set(:pool, Concurrent::FixedThreadPool.new(1, max_queue: 0, fallback_policy: :caller_runs))
    Sinatra::Application
  end

  def test_renders_pages
    WebMock.allow_net_connect!
    [
      '/version',
      '/robots.txt',
      '/',
      '/css/main.css',
      '/context',
      '/remotes'
    ].each do |p|
      get(p)
      assert(last_response.ok?)
    end
  end

  def test_not_found
    WebMock.allow_net_connect!
    get('/unknown_path')
    assert_equal(404, last_response.status)
    assert_equal('text/html;charset=utf-8', last_response.content_type)
  end

  def test_200_user_pages
    WebMock.allow_net_connect!
    login('bill')
    ['/home', '/key', '/log', '/invoice', '/api', '/btc'].each do |p|
      get(p)
      assert_equal(200, last_response.status, "#{p} fails: #{last_response.body}")
    end
  end

  def test_302_user_pages
    WebMock.allow_net_connect!
    login('nick')
    ['/pull'].each do |p|
      get(p)
      assert_equal(302, last_response.status, "#{p} fails: #{last_response.body}")
    end
  end

  def test_api_code
    WebMock.allow_net_connect!
    keygap = login('poly')
    post('/do-api', 'keygap=' + keygap)
    assert_equal(200, last_response.status, last_response.body)
    assert(last_response.body.include?('X-Zold-Wts:'), last_response.body)
  end

  def test_fetch_rsa_key_via_restful_api
    WebMock.allow_net_connect!
    keygap = login('anna')
    post('/do-api-token', 'keygap=' + keygap)
    assert_equal(200, last_response.status, last_response.body)
    token = last_response.body
    set_cookie('glogin=')
    assert_raises { get('/id_rsa') }
    header('X-Zold-WTS', token)
    get('/id_rsa')
    assert_equal(200, last_response.status, last_response.body)
  end

  def test_buy_zld
    WebMock.allow_net_connect!
    Dir.mktmpdir 'test' do |dir|
      wallets = Zold::Wallets.new(File.join(dir, 'wallets'))
      boss = User.new(
        '0crat', Item.new('0crat', Dynamo.new.aws, log: test_log),
        Sinatra::Application.settings.wallets, log: test_log
      )
      boss.create
      login = 'jeff009'
      user = User.new(
        login, Item.new(login, Dynamo.new.aws, log: test_log),
        wallets, log: test_log
      )
      user.create
      keygap = user.keygap
      user.confirm(keygap)
      user.item.save_btc('1N1R2HP9JD4LvAtp7rTkpRqF19GH7PH2ZF')
      get(
        '/btc-hook?' + {
          'transaction_hash': 'c3c0a51ff985618dd8373eadf3540fd1bea44d676452dbab47fe0cc07209547d',
          'zold_user': login,
          'confirmations': 10,
          'value': 27_900
        }.map { |k, v| "#{k}=#{CGI.escape(v.to_s)}" }.join('&')
      )
      assert_equal(200, last_response.status, last_response.body)
      assert_equal('*ok*', last_response.body)
    end
  end

  def test_sell_zld
    skip
    WebMock.allow_net_connect!
    name = 'jeff079'
    login(name)
    boss = User.new(
      '0crat', Item.new('0crat', Dynamo.new.aws, log: test_log),
      Sinatra::Application.settings.wallets, log: test_log
    )
    boss.create
    user = User.new(
      name, Item.new(name, Dynamo.new.aws, log: test_log),
      Sinatra::Application.settings.wallets, log: test_log
    )
    user.create
    keygap = user.keygap
    user.confirm(keygap)
    Sinatra::Application.settings.wallets.acq(user.item.id) do |w|
      w.add(
        Zold::Txn.new(
          1,
          Time.now,
          Zold::Amount.new(zld: 100.0),
          'NOPREFIX', Zold::Id.new, '-'
        )
      )
    end
    post(
      '/do-sell',
      {
        'amount': '1',
        'btc': '1N1R2HP9JD4LvAtp7rTkpRqF19GH7PH2ZF',
        'keygap': keygap
      }.map { |k, v| "#{k}=#{CGI.escape(v.to_s)}" }.join('&')
    )
    assert_equal(302, last_response.status, last_response.body)
  end

  private

  def login(name)
    set_cookie('glogin=' + name)
    get('/create')
    assert_equal(302, last_response.status, last_response.body)
    get('/keygap')
    assert_equal(200, last_response.status, last_response.body)
    keygap = last_response.body
    get('/do-confirm?keygap=' + keygap)
    assert_equal(302, last_response.status, last_response.body)
    get('/id')
    assert_equal(200, last_response.status, last_response.body)
    keygap
  end
end
