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

STDOUT.sync = true

require 'backtrace'
require 'concurrent'
require 'geocoder'
require 'get_process_mem'
require 'glogin'
require 'haml'
require 'json'
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
require_relative 'objects/pgsql'
require_relative 'objects/tokens'
require_relative 'objects/user'
require_relative 'objects/wts'
require_relative 'version'

if ENV['RACK_ENV'] != 'test'
  require 'rack/ssl'
  use Rack::SSL
end

configure do
  Zold::Hands.start
  Haml::Options.defaults[:format] = :xhtml
  config = if ENV['RACK_ENV'] == 'test'
    {
      'pkey_secret' => 'fake',
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
      'pgsql' => {
        'host' => 'localhost',
        'port' => 0,
        'user' => 'test',
        'dbname' => 'test',
        'password' => 'test'
      },
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
  set :config, config
  set :logging, true
  set :show_exceptions, false
  set :raise_errors, false
  set :dump_errors, false
  set :server_settings, timeout: 25
  set :log, Zold::Log::REGULAR.dup
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
  set :copies, File.join(settings.root, '.zold-wts/copies')
  set :pgsql, WTS::Pgsql.new(
    host: settings.config['pgsql']['host'],
    port: settings.config['pgsql']['port'],
    dbname: settings.config['pgsql']['dbname'],
    user: settings.config['pgsql']['user'],
    password: settings.config['pgsql']['password']
  ).start(1)
  set :payouts, WTS::Payouts.new(settings.pgsql, log: settings.log)
  set :daemons, WTS::Daemons.new(settings.pgsql, log: settings.log)
  set :codec, GLogin::Codec.new(config['api_secret'])
  set :zache, Zache.new(dirty: true)
  set :pool, Concurrent::FixedThreadPool.new(16, max_queue: 64, fallback_policy: :abort)
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
      settings.telepost.run
    end
  end
  settings.telepost.spam(
    '[WTS](https://wts.zold.io) server software',
    "[#{WTS::VERSION}](https://github.com/zold-io/wts.zold.io/releases/tag/#{WTS::VERSION})",
    'has been deployed and starts to work;',
    "Zold version is [#{Zold::VERSION}](https://rubygems.org/gems/zold/versions/#{Zold::VERSION}),",
    "the protocol is `#{Zold::PROTOCOL}`"
  )
end

before '/*' do
  @locals = {
    ver: WTS::VERSION,
    login_link: settings.glogin.login_uri,
    wallets: settings.wallets,
    remotes: settings.remotes,
    pool: settings.pool,
    mem: settings.zache.get(:mem, lifetime: 60) { GetProcessMem.new.bytes.to_i },
    total_mem: settings.zache.get(:total_mem, lifetime: 60) { Total::Mem.new.bytes }
  }
  cookies[:glogin] = params[:glogin] if params[:glogin]
  if cookies[:glogin]
    begin
      @locals[:guser] = GLogin::Cookie::Closed.new(
        cookies[:glogin],
        settings.config['github']['encryption_secret'],
        context
      ).to_user[:login]&.downcase
    rescue OpenSSL::Cipher::CipherError => _
      @locals.delete(:guser)
    end
  end
  header = request.env['HTTP_X_ZOLD_WTS'] || cookies[:wts] || nil
  if header
    login, token = header.strip.split('-', 2)
    unless user(login).item.exists?
      settings.log.info("API login: User #{login} is absent")
      return
    end
    unless settings.tokens.get(login) == token
      settings.log.info("Invalid token #{token.inspect} of #{login}")
      return
    end
    @locals[:guser] = login.downcase
  end
  cookies[:ref] = params[:ref] if params[:ref]
  cookies[:utm_source] = params[:utm_source] if params[:utm_source]
  cookies[:utm_medium] = params[:utm_medium] if params[:utm_medium]
  cookies[:utm_campaign] = params[:utm_campaign] if params[:utm_campaign]
  request.env['rack.request.query_hash'].each do |k, v|
    raise WTS::UserError, "E101: The param #{k.inspect} can't be empty" if v.nil?
    raise WTS::UserError, "E102: Invalid encoding of #{k.inspect} param" unless v.valid_encoding?
  end
end

after do
  headers['Access-Control-Allow-Origin'] = '*'
end

get '/' do
  redirect '/home' if @locals[:guser]
  haml :index, layout: :layout, locals: merged(
    page_title: 'wts'
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
    usd_rate: settings.zache.exists?(:rate) ? settings.zache.get(:rate)[:usd_rate] : nil
  )
end

get '/key' do
  haml :key, layout: :layout, locals: merged(
    page_title: title('key')
  )
end

get '/id' do
  content_type 'text/plain'
  confirmed_user.item.id.to_s
end

get '/balance' do
  content_type 'text/plain'
  confirmed_user.wallet(&:balance).to_i.to_s
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
    IO.read(w.path)
  end
end

get '/api' do
  prohibit('api')
  haml :api, layout: :layout, locals: merged(
    page_title: title('api'),
    token: "#{confirmed_user.login}-#{settings.tokens.get(confirmed_user.login)}"
  )
end

get '/api-reset' do
  prohibit('api')
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
  prohibit('buy-sell')
  haml :buy_sell, layout: :layout, locals: merged(
    page_title: title('buy/sell')
  )
end

get '/log' do
  content_type 'text/plain', charset: 'utf-8'
  user_log.content + "\n\n\n" + [
    'If you see any errors here, which you don\'t understand,',
    'please submit an issue to our GitHub repository here and copy the entire log over there:',
    'https://github.com/zold-io/wts.zold.io/issues;',
    'we need your feedback in order to make our system better;',
    'you can also discuss it in our Telegram group: https://t.me/zold_io.'
  ].join(' ')
end

get '/remotes' do
  haml :remotes, layout: :layout, locals: merged(
    page_title: '/remotes'
  )
end

private

def rate
  settings.toggles.get('rate', '0.00025').to_f
end

def fee
  known? ? 0.02 : 0.08
end

def title(suffix = '')
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

def country
  country = Geocoder.search(request.ip).first
  country.nil? ? '??' : country.country.to_s
end

def flash(uri, msg, error: false)
  cookies[:flash_msg] = msg
  cookies[:flash_color] = error ? 'darkred' : 'darkgreen'
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
  Zold::Http.new(uri: 'https://www.0crat.com/known/' + login).get.code == 200
end

# This user is identified in Zerocracy.
def kyc?(login = @locals[:guser])
  return false unless login
  return true if ENV['RACK_ENV'] == 'test'
  return true if login == settings.config['rewards']['login']
  return true if login == settings.config['exchange']['login']
  res = Zold::Http.new(uri: 'https://www.0crat.com/known/' + login).get
  return false unless res.code == 200
  Zold::JsonPage.new(res.body).to_hash['identified']
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

def prohibit(feature)
  return unless settings.toggles.get("stop:#{feature}", 'no') == 'yes'
  raise WTS::UserError, "E177: This feature \"#{feature}\" is temporarily disabled, sorry"
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
  "full log is [here](http://wts.zold.io/output?id=#{jid})"
end

def register_referral(login)
  return unless cookies[:ref] && !settings.referrals.exists?(login)
  settings.referrals.register(
    login, cookies[:ref],
    source: cookies[:utm_source], medium: cookies[:utm_medium], campaign: cookies[:utm_campaign]
  )
end

def github_exists?(login)
  Zold::Http.new(uri: "https://api.github.com/users/#{login}").get.status == 200
end

def callback(args)
  uri = params[:callback]
  return if uri.nil?
  uri = URI.parse(uri)
  query = URI.decode_www_form(String(uri.query))
  args.each { |k, v| query << [k, v] }
  uri.query = URI.encode_www_form(query)
  res = Zold::Http.new(uri: uri.to_s).get
  raise "198: Callback failure with HTTP code #{res.status} at #{uri}" unless res.status == 200
end

require_relative 'front/front_bonuses'
require_relative 'front/front_btc'
require_relative 'front/front_callbacks'
require_relative 'front/front_errors'
require_relative 'front/front_jobs'
require_relative 'front/front_login'
require_relative 'front/front_migrate'
require_relative 'front/front_misc'
require_relative 'front/front_pay'
require_relative 'front/front_paypal'
require_relative 'front/front_quick'
require_relative 'front/front_rate'
require_relative 'front/front_start'
require_relative 'front/front_toggles'
