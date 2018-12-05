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
    get('/unknown_path')
    assert_equal(404, last_response.status)
    assert_equal('text/html;charset=utf-8', last_response.content_type)
  end

  def test_200_user_pages
    login('bill')
    ['/home', '/key', '/log', '/invoice', '/api', '/coinbase'].each do |p|
      get(p)
      assert_equal(200, last_response.status, "#{p} fails: #{last_response.body}")
    end
  end

  def test_302_user_pages
    login('nick')
    ['/pull'].each do |p|
      get(p)
      assert_equal(302, last_response.status, "#{p} fails: #{last_response.body}")
    end
  end

  def test_api_code
    keygap = login('poly')
    post('/do-api', 'keygap=' + keygap)
    assert_equal(200, last_response.status, last_response.body)
    assert(last_response.body.include?('X-Zold-Wts:'), last_response.body)
  end

  def test_fetch_rsa_key_via_restful_api
    keygap = login('anna')
    post('/do-api-token', 'keygap=' + keygap)
    assert_equal(200, last_response.status, last_response.body)
    token = last_response.body
    set_cookie('glogin=')
    header('X-Zold-WTS', token)
    post('/id_rsa')
    assert_equal(200, last_response.status, last_response.body)
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
