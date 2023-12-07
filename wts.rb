# Copyright (c) 2018-2023 Zerocracy
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

$stdout.sync = true

require 'backtrace'
require 'concurrent'
require 'get_process_mem'
require 'geoplugin'
require 'glogin'
require 'haml'
require 'iri'
require 'json'
require 'pgtk/pool'
require 'rack/ssl'
require 'raven'
require 'sass'
require 'securerandom'
require 'sinatra'
require 'sinatra/cookies'
require 'telebot'
require 'telepost'
require 'tempfile'
require 'total'
require 'uri'
require 'yaml'
require 'zold'
require 'zold/amount'
require 'zold/cached_wallets'
require 'zold/hands'
require 'zold/json_page'
require 'zold/log'
require 'zold/remotes'
require 'zold/sync_wallets'
require_relative 'objects/daemons'
require_relative 'objects/item'
require_relative 'objects/ops'
require_relative 'objects/payouts'
require_relative 'objects/tokens'
require_relative 'objects/user'
require_relative 'objects/wts'
require_relative 'objects/dollars'
require_relative 'objects/rate'
require_relative 'version'

if ENV['RACK_ENV'] != 'test'
  require 'rack/ssl'
  use Rack::SSL
end

# See https://github.com/baldowl/rack_csrf
require 'rack/csrf'
use Rack::Session::Cookie
use Rack::Csrf, raise: true, skip_if: lambda { |request|
  request.env.key?('HTTP_X_ZOLD_WTS')
}

configure do
  Zold::Hands.start
  Haml::Options.defaults[:format] = :xhtml
  config = if ENV['RACK_ENV'] == 'test'
    {
      'kyc' => [],
      'pkey_secret' => 'fake',
      'geoplugin_token' => '?',
      'rewards' => {
        'login' => 'zonuses',
        'keygap' => '?'
      },
      'exchange' => {
        'login' => 'zoldwts',
        'keygap' => '?'
      },
      'zerocrat' => {
        'login' => '0crat',
        'keygap' => '?'
      },
      'paypal' => {
        'id' => '?',
        'secret' => '?'
      },
      'github' => {
        'client_id' => '?',
        'client_secret' => '?',
        'encryption_secret' => ''
      },
      'api_secret' => 'test',
      'sentry' => '',
      'telegram' => {
        'token' => '',
        'chat' => '111'
      }
    }
  else
    YAML.safe_load(File.open(File.join(File.dirname(__FILE__), 'config.yml')))
  end
  if ENV['RACK_ENV'] != 'test'
    Raven.configure do |c|
      c.dsn = config['sentry']
      c.release = WTS::VERSION
    end
  end
  set :bind, '0.0.0.0'
  set :server, :thin
  set :config, config
  set :logging, true
  set :show_exceptions, false
  set :raise_errors, false
  set :dump_errors, false
  set :server_settings, timeout: 25
  set :log, ENV['RACK_ENV'] == 'test' ? Zold::Log::VERBOSE.dup : Zold::Log::REGULAR.dup
  set :log, Zold::Log::NULL if ENV['TEST_QUIET_LOG']
  set :glogin, GLogin::Auth.new(
    config['github']['client_id'],
    config['github']['client_secret'],
    'https://wts.zold.io/github-callback'
  )
  set :wallets, Zold::SyncWallets.new(
    Zold::CachedWallets.new(
      Zold::Wallets.new(
        File.join(settings.root, '.zold-wts/wallets')
      )
    )
  )
  set :remotes, Zold::Remotes.new(
    file: File.join(settings.root, '.zold-wts/remotes'),
    network: ENV['RACK_ENV'] == 'test' ? 'test' : 'zold'
  )
  if File.exist?('target/pgsql-config.yml')
    set :pgsql, Pgtk::Pool.new(
      Pgtk::Wire::Yaml.new(File.join(__dir__, 'target/pgsql-config.yml')),
      log: settings.log
    )
  else
    set :pgsql, Pgtk::Pool.new(
      Pgtk::Wire::Env.new('DATABASE_URL'),
      log: settings.log
    )
  end
  settings.pgsql.start(4)
  set :copies, File.join(settings.root, '.zold-wts/copies')
  set :payouts, WTS::Payouts.new(settings.pgsql, log: settings.log)
  set :daemons, WTS::Daemons.new(settings.pgsql, log: settings.log)
  set :codec, GLogin::Codec.new(config['api_secret'], base64: true)
  set :zache, Zache.new(dirty: true)
  if settings.config['telegram']['token'].empty?
    set :telepost, Telepost::Fake.new
  else
    chat = '@zold_wts'
    set :telepost, Telepost.new(
      settings.config['telegram']['token'],
      chats: [chat]
    )
    settings.daemons.start('telepost') do
      settings.log.info("Starting Telegram chatbot at #{chat}...")
      settings.telepost.run do |cht, _msg|
        settings.telepost.post(
          cht,
          'This bot is not answering here.',
          'All it does is posting news to this channel: [@zold_wts](https://t.me/zold_wts).',
          'Don\'t hesitate to subscribe and stay informed about everything that is going on',
          'in https://wts.zold.io.'
        )
      end
    end
  end
  settings.telepost.spam(
    '👋 [WTS](https://wts.zold.io) server software',
    "[#{WTS::VERSION}](https://github.com/zold-io/wts.zold.io/releases/tag/#{WTS::VERSION})",
    'has been deployed and starts working;',
    "Zold version is [#{Zold::VERSION}](https://rubygems.org/gems/zold/versions/#{Zold::VERSION}),",
    "the protocol is `#{Zold::PROTOCOL}`;",
    "#{format('%.01f', Total::Mem.new.bytes.to_f / (1024 * 1024 * 1024))}Gb memory total;",
    "#{Concurrent.physical_processor_count} CPUs"
  )
end

after do
  headers['Access-Control-Allow-Origin'] = '*'
end

get '/' do
  redirect '/home' if @locals[:guser]
  haml :index, layout: :layout, locals: merged(
    page_title: 'wts',
    rate: WTS::Rate.new(settings.toggles).to_f
  )
end

get '/home' do
  unless user.item.exists?
    flash('/create', 'Time to create your wallet') unless File.exist?(latch(user.login))
    return haml :busy, layout: :layout, locals: merged(
      page_title: title('busy')
    )
  end
  flash('/confirm', 'Time to save your keygap') unless user.confirmed?
  haml :home, layout: :layout, locals: merged(
    page_title: title,
    start: params[:start] ? Time.parse(params[:start]) : nil,
    usd_rate: WTS::Rate.new(settings.toggles).to_f * price
  )
end

get '/key' do
  haml :key, layout: :layout, locals: merged(
    page_title: title('key')
  )
end

get '/id' do
  content_type 'text/plain'
  return Zold::Id::ROOT.to_s if user.fake?
  user.item.id.to_s
end

get '/balance' do
  content_type 'text/plain'
  confirmed_user.wallet(&:balance).to_i.to_s
end

get '/head.json' do
  content_type 'application/json'
  confirmed_user.wallet do |wallet|
    JSON.pretty_generate(
      id: wallet.id.to_s,
      mtime: wallet.mtime.utc.iso8601,
      age: wallet.age.to_s,
      size: wallet.size,
      digest: wallet.digest,
      balance: wallet.balance.to_i,
      txns: wallet.txns.count,
      taxes: Zold::Tax.new(wallet).paid.to_i,
      debt: Zold::Tax.new(wallet).debt.to_i
    )
  end
end

get '/find' do
  content_type 'text/plain'
  confirmed_user.wallet do |wallet|
    wallet.txns.select do |t|
      matches = false
      matches |= params[:id] && Regexp.new(params[:id]).match?(t.id.to_s)
      matches |= params[:date] && Regexp.new(params[:date]).match?(t.date.utc.iso8601)
      matches |= params[:amount] && Regexp.new(params[:amount]).match?(t.amount.to_i.to_s)
      matches |= params[:prefix] && Regexp.new(params[:prefix]).match?(t.prefix)
      matches |= params[:bnf] && Regexp.new(params[:bnf]).match?(t.bnf.to_s)
      matches |= params[:details] && Regexp.new(params[:details]).match?(t.details)
      matches
    end
  end.join("\n")
end

get '/txns.json' do
  content_type 'application/json'
  confirmed_user.wallet do |wallet|
    list = wallet.txns
    list.reverse! if params[:sort] && params[:sort] == 'desc'
    JSON.pretty_generate(
      list.map do |t|
        t.to_json.merge(tid: t.amount.negative? ? "#{wallet.id}:#{t.id}" : "#{t.bnf}:#{t.id}")
      end
    )
  end
end

get '/txn.json' do
  tid = params[:tid]
  raise WTS::UserError, "E193: Parameter 'tid' is mandatory" if tid.nil?
  source, id = tid.split(':')
  raise WTS::UserError, "E199: The wallet ID #{source.inspect} is wrong" unless /^[0-9a-f]{16}$/.match?(source)
  raise WTS::UserError, "E200: The transaction ID #{id.inspect} is wrong" unless /^[0-9]+$/.match?(id)
  id = id.to_i
  content_type 'application/json'
  JSON.pretty_generate(settings.gl.txn(source, id))
end

get '/id_rsa' do
  response.headers['Content-Type'] = 'application/octet-stream'
  response.headers['Content-Disposition'] = 'attachment; filename=id_rsa'
  confirmed_user.item.key(keygap).to_s
end

get '/download' do
  response.headers['Content-Type'] = 'application/octet-stream'
  response.headers['Content-Disposition'] = "attachment; filename=#{confirmed_user.item.id}#{Zold::Wallet::EXT}"
  confirmed_user.wallet do |w|
    File.read(w.path)
  end
end

get '/api' do
  features('api')
  haml :api, layout: :layout, locals: merged(
    page_title: title('api'),
    token: "#{confirmed_user.login}-#{settings.tokens.get(confirmed_user.login)}"
  )
end

get '/api-reset' do
  features('api')
  settings.tokens.reset(confirmed_user.login)
  settings.telepost.spam(
    "API token has been reset by #{title_md}",
    "from #{anon_ip}"
  )
  flash('/api', 'You got a new API token')
end

get '/invoice' do
  haml :invoice, layout: :layout, locals: merged(
    page_title: title('invoice')
  )
end

get '/invoice.json' do
  inv = user.invoice
  prefix, id = inv.split('@')
  content_type 'application/json'
  JSON.pretty_generate(prefix: prefix, invoice: inv, id: id)
end

get '/sql' do
  raise WTS::UserError, 'E129: You are not allowed to see this' unless vip?
  query = params[:query] || 'SELECT * FROM txn LIMIT 16'
  haml :sql, layout: :layout, locals: merged(
    page_title: title('SQL'),
    query: query,
    result: settings.pgsql.exec(query)
  )
end

get '/payouts' do
  haml :payouts, layout: :layout, locals: merged(
    page_title: title('payouts'),
    payouts: settings.payouts,
    system_limits: settings.toggles.get('system-limits'),
    limits: settings.toggles.get('limits'),
    system_consumed: settings.payouts.system_consumed,
    consumed: settings.payouts.consumed(confirmed_user.login)
  )
end

get '/buy-sell' do
  features('buy-sell')
  haml :buy_sell, layout: :layout, locals: merged(
    page_title: title('buy/sell')
  )
end

get '/log' do
  content_type 'text/plain', charset: 'utf-8'
  msg = [
    'If you see any errors here, which you don\'t understand,',
    'please submit an issue to our GitHub repository here and copy the entire log over there:',
    'https://github.com/zold-io/wts.zold.io/issues;',
    'we need your feedback in order to make our system better;',
    'you can also discuss it in our Telegram group: https://t.me/zold_io.'
  ].join(' ')
  "#{user_log.content}\n\n\n#{msg}"
end

get '/remotes' do
  haml :remotes, layout: :layout, locals: merged(
    page_title: '/remotes'
  )
end

def exfee
  settings.toggles.get(known? ? 'exfee-small' : 'exfee', '0.08').to_f
end

def title(suffix = '')
  return 'SANDBOX' if user.fake?
  (user.mobile? ? "+#{user.login}" : "@#{user.login}") + (suffix.empty? ? '' : '/' + suffix)
end

def title_md(u = user)
  if /^[0-9]{6,}$/.match?(u.login)
    "+#{u.login.gsub(/.{3}$/, 'xxx')}"
  else
    "[@#{u.login}](https://github.com/#{u.login})"
  end
end

def anon_ip
  "`#{request.ip.to_s.gsub(/\.[0-9]+$/, '.xx')}` (#{country})"
end

def country(ip = request.ip)
  settings.zache.get("ip_to_country:#{ip}") do
    geo = Geoplugin.new(request.ip, ssl: true, key: settings.config['geoplugin_token'])
    geo.nil? ? '??' : geo.countrycode
  rescue StandardError
    '??'
  end
end

def flash(uri, msg, error: false)
  cookies[:flash_msg] = msg
  cookies[:flash_color] = error ? 'firebrick' : 'seagreen'
  redirect(uri, error ? 303 : 302) unless params[:noredirect]
  msg
end

def context
  "#{request.ip} #{request.user_agent} #{WTS::VERSION}"
end

def merged(hash = {})
  out = @locals.merge(hash)
  out[:local_assigns] = out
  if cookies[:flash_msg]
    out[:flash_msg] = cookies[:flash_msg]
    cookies.delete(:flash_msg)
  end
  out[:flash_color] = cookies[:flash_color] || 'darkgreen'
  cookies.delete(:flash_color)
  out
end

def user_log(u = user.login)
  WTS::FileLog.new(File.join(settings.root, ".zold-wts/logs/#{u}"))
end

def user(login = @locals[:guser])
  raise WTS::UserError, 'E173: You have to login first' unless login
  WTS::User.new(
    login, WTS::Item.new(login, settings.pgsql, log: user_log(login)),
    settings.wallets, log: user_log(login)
  )
end

def confirmed_user(login = @locals[:guser])
  u = user(login)
  raise WTS::UserError, "E174: You, #{login}, have to confirm your keygap first" unless u.confirmed?
  u
end

# This user is known as Zerocracy contributor.
def known?(login = @locals[:guser])
  return false unless login
  return true if ENV['RACK_ENV'] == 'test'
  return true if login == settings.config['rewards']['login']
  return true if login == settings.config['exchange']['login']
  return true if settings.config['kyc'].include?(login)
  settings.zache.get("#{login}_known?", lifetime: 5 * 60) do
    code = Zold::Http.new(
      uri: Iri.new('https://www.0crat.com/known/').append(login.downcase).to_s
    ).get(timeout: 16).code
    case code
    when 200
      true
    when 404
      false
    else
      raise WTS::UserError, "E226: Something is wrong with 0crat.com, HTTP code is #{code}"
    end
  end
end

# This user is identified in Zerocracy.
def kyc?(login = @locals[:guser])
  return false unless login
  return true if ENV['RACK_ENV'] == 'test'
  return true if login == settings.config['rewards']['login']
  return true if login == settings.config['exchange']['login']
  return true if settings.config['kyc'].include?(login)
  settings.zache.get("#{login}_kyc?", lifetime: 5 * 60) do
    res = Zold::Http.new(
      uri: Iri.new('https://www.0crat.com/known/').append(login.downcase).to_s
    ).get(timeout: 16)
    res.code == 200 && Zold::JsonPage.new(res.body).to_hash['identified']
  end
end

def keygap
  gap = params[:keygap]
  raise WTS::UserError, 'E175: Keygap is required' if gap.nil?
  begin
    confirmed_user.item.key(gap).to_s
  rescue StandardError => e
    raise WTS::UserError, "E176: This doesn\'t seem to be a valid keygap: '#{'*' * gap.length}' (#{e.class.name})"
  end
  gap
end

def latch(login = @locals[:guser])
  File.join(settings.root, "latch/#{login}")
end

def network
  ENV['RACK_ENV'] == 'test' ? 'test' : 'zold'
end

def ops(u = user, log: user_log(u.login))
  WTS::Ops.new(
    u.item,
    u,
    settings.wallets,
    settings.remotes,
    settings.copies,
    log: log,
    network: network
  )
end

# Make sure these features are enabled and let the execution
# continue. If at least one of them is prohibited in the Toggles,
# an exception will be raised.
def features(*list)
  return if @locals[:guser] && vip?
  list.each do |f|
    next unless settings.toggles.get("stop:#{f}", 'no') == 'yes'
    raise WTS::UserError, "E177: This feature \"#{f}\" is temporarily disabled, sorry"
  end
end

def safe_md(txt)
  txt.gsub(/[_*`]/, ' ')
end

def vip?(login = user.login)
  return true if ENV['RACK_ENV'] == 'test'
  return true if login == 'yegor256'
  settings.toggles.get('vip').split(',').include?(login.downcase)
end

def job_link(jid)
  "the full log is [here](https://wts.zold.io/output?id=#{jid})"
end

require_relative 'front/front_auto_pull'
require_relative 'front/front_bonuses'
require_relative 'front/front_btc'
require_relative 'front/front_admin'
require_relative 'front/front_callbacks'
require_relative 'front/front_errors'
require_relative 'front/front_jobs'
require_relative 'front/front_login'
require_relative 'front/front_migrate'
require_relative 'front/front_misc'
require_relative 'front/front_pay'
require_relative 'front/front_paypal'
require_relative 'front/front_push'
require_relative 'front/front_quick'
require_relative 'front/front_rate'
require_relative 'front/front_receipt'
require_relative 'front/front_start'
require_relative 'front/front_toggles'
require_relative 'front/front_upwork'
require_relative 'front/helpers'
