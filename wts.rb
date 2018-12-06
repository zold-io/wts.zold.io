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

STDOUT.sync = true

require 'haml'
require 'coinbase/wallet'
require 'sinatra'
require 'sinatra/cookies'
require 'sass'
require 'json'
require 'backtrace'
require 'raven'
require 'glogin'
require 'base64'
require 'concurrent'
require 'tempfile'
require 'rack/ssl'
require 'zold/log'
require 'zold/remotes'
require 'zold/amount'
require 'zold/wallets'
require 'zold/sync_wallets'
require 'zold/cached_wallets'
require 'zold/remotes'

require_relative 'version'
require_relative 'objects/item'
require_relative 'objects/user'
require_relative 'objects/dynamo'
require_relative 'objects/ops'
require_relative 'objects/async_ops'
require_relative 'objects/safe_ops'
require_relative 'objects/latch_ops'
require_relative 'objects/update_ops'
require_relative 'objects/versioned_ops'
require_relative 'objects/file_log'
require_relative 'objects/tee_log'

if ENV['RACK_ENV'] != 'test'
  require 'rack/ssl'
  use Rack::SSL
end

configure do
  Haml::Options.defaults[:format] = :xhtml
  config = if ENV['RACK_ENV'] == 'test'
    {
      'rewards' => {
        'login' => '0crat',
        'keygap' => '?'
      },
      'github' => {
        'client_id' => '?',
        'client_secret' => '?',
        'encryption_secret' => ''
      },
      'api_secret' => 'test',
      'sentry' => '',
      'dynamo' => {
        'key' => '?',
        'secret' => '?'
      },
      'blockchain' => {
        'xpub' => '?',
        'key' => '?'
      },
      'coinbase' => {
        'key' => '?',
        'secret' => '?',
        'account' => '?'
      }
    }
  else
    YAML.safe_load(File.open(File.join(File.dirname(__FILE__), 'config.yml')))
  end
  if ENV['RACK_ENV'] != 'test'
    Raven.configure do |c|
      c.dsn = config['sentry']
      c.release = VERSION
    end
  end
  set :config, config
  set :logging, true
  set :server_settings, timeout: 25
  set :dynamo, Dynamo.new(config).aws
  set :glogin, GLogin::Auth.new(
    config['github']['client_id'],
    config['github']['client_secret'],
    'https://wts.zold.io/github-callback'
  )
  set :wallets, Zold::CachedWallets.new(
    Zold::SyncWallets.new(
      Zold::Wallets.new(File.join(settings.root, '.zold-wts/wallets'))
    )
  )
  set :remotes, Zold::Remotes.new(file: File.join(settings.root, '.zold-wts/remotes'), network: 'zold')
  set :copies, File.join(settings.root, '.zold-wts/copies')
  set :codec, GLogin::Codec.new(config['api_secret'])
  set :pool, Concurrent::FixedThreadPool.new(16, max_queue: 64, fallback_policy: :abort)
  set :log, Zold::Log::REGULAR.dup
  Thread.new do
    loop do
      sleep 60 * 60
      begin
        pay_hosting_bonuses
      rescue StandardError => e
        Raven.capture_exception(e)
        settings.log.error(Backtrace.new(e))
      end
    end
  end
end

before '/*' do
  @locals = {
    ver: VERSION,
    login_link: settings.glogin.login_uri,
    wallets: settings.wallets,
    remotes: settings.remotes,
    pool: settings.pool
  }
  header = request.env['HTTP_X_ZOLD_WTS']
  if header
    begin
      login, keygap = settings.codec.decrypt(header).split(' ')
      @params[:glogin] = login
      @locals[:keygap] = keygap
      settings.log.info("HTTP authentication header of @#{login} detected from #{request.ip}")
    rescue OpenSSL::Cipher::CipherError => _
      error 400
    end
  end
  cookies[:glogin] = params[:glogin] if params[:glogin]
  if cookies[:glogin]
    begin
      @locals[:guser] = GLogin::Cookie::Closed.new(
        cookies[:glogin],
        settings.config['github']['encryption_secret'],
        context
      ).to_user[:login]
    rescue OpenSSL::Cipher::CipherError => _
      @locals.delete(:guser)
    end
  end
end

after do
  headers['Access-Control-Allow-Origin'] = '*'
end

get '/github-callback' do
  cookies[:glogin] = GLogin::Cookie::Open.new(
    settings.glogin.user(params[:code]),
    settings.config['github']['encryption_secret'],
    context
  ).to_s
  flash('/', 'You have been logged in')
end

get '/logout' do
  cookies.delete(:glogin)
  flash('/', 'You have been logged out')
end

get '/' do
  redirect '/home' if @locals[:guser]
  haml :index, layout: :layout, locals: merged(
    title: 'wts'
  )
end

get '/home' do
  flash('/create', 'Time to create your wallet') unless user.item.exists?
  haml :home, layout: :layout, locals: merged(
    title: '@' + @locals[:guser],
    start: params[:start] ? Time.parse(params[:start]) : nil
  )
end

get '/create' do
  user.create
  pay_bonus
  ops.push
  log.info("Wallet #{user.item.id} created and pushed by @#{@locals[:guser]}\n")
  flash('/', "Wallet #{user.item.id} created and pushed")
end

get '/confirm' do
  flash('/', 'You have done this already, your keygap has been generated') if user.confirmed?
  haml :confirm, layout: :layout, locals: merged(
    title: '@' + user.login + '/keygap'
  )
end

get '/do-confirm' do
  flash('/', 'You have done this already, your keygap has been generated') if user.confirmed?
  user.confirm(params[:keygap])
  log.info("Account confirmed for @#{confirmed_user.login}\n")
  flash('/', 'The account has been confirmed')
end

get '/keygap' do
  flash('/', 'We don\'t have it in the database anymore') if user.item.wiped?
  content_type 'text/plain'
  user.item.keygap
end

get '/pay' do
  haml :pay, layout: :layout, locals: merged(
    title: '@' + confirmed_user.login + '/pay'
  )
end

post '/do-pay' do
  if params[:bnf].match?(/[a-f0-9]{16}/)
    bnf = Zold::Id.new(params[:bnf])
  else
    login = params[:bnf].strip.downcase.gsub(/^@/, '')
    raise UserError, "Invalid GitHub user name: '#{params[:bnf]}'" unless login =~ /^[a-z0-9-]{3,32}$/
    friend = user(login)
    unless friend.item.exists?
      friend.create
      ops(friend).push
    end
    bnf = friend.item.id
  end
  amount = Zold::Amount.new(zld: params[:amount].to_f)
  details = params[:details]
  ops.pay(keygap, bnf, amount, details)
  log.info("Payment made by @#{confirmed_user.login} to #{bnf} for #{amount}\n \n")
  flash('/', "Payment has been sent to #{bnf} for #{amount}")
end

get '/pull' do
  ops.pull
  log.info("Wallet #{user.item.id} pulled by @#{confirmed_user.login}\n \n")
  flash('/', "Your wallet #{user.item.id} will be pulled soon")
end

get '/key' do
  haml :key, layout: :layout, locals: merged(
    title: '@' + confirmed_user.login + '/key'
  )
end

get '/id' do
  content_type 'text/plain'
  confirmed_user.item.id.to_s
end

get '/balance' do
  error 404 unless confirmed_user.wallet(&:exists?)
  content_type 'text/plain'
  confirmed_user.wallet(&:balance).to_i
end

get '/find' do
  error 404 unless confirmed_user.wallet(&:exists?)
  content_type 'text/plain'
  confirmed_user.wallet do |wallet|
    wallet.txns.select do |t|
      matches = false
      matches |= params[:id] && Regexp.new(params[:id]).match(t.id.to_s)
      matches |= params[:date] && Regexp.new(params[:date]).match(t.date.utc.iso8601)
      matches |= params[:amount] && Regexp.new(params[:amount]).match(t.amount.to_i.to_s)
      matches |= params[:prefix] && Regexp.new(params[:prefix]).match(t.prefix)
      matches |= params[:bnf] && Regexp.new(params[:bnf]).match(t.bnf.to_s)
      matches |= params[:details] && Regexp.new(params[:details]).match(t.details)
      matches
    end
  end.join("\n")
end

post '/id_rsa' do
  content_type 'text/plain'
  confirmed_user.item.key(keygap).to_s
end

get '/api' do
  haml :api, layout: :layout, locals: merged(
    title: '@' + confirmed_user.login + '/api'
  )
end

post '/do-api' do
  haml :do_api, layout: :layout, locals: merged(
    title: '@' + confirmed_user.login + '/api',
    code: settings.codec.encrypt("#{confirmed_user.login} #{keygap}")
  )
end

post '/do-api-token' do
  content_type 'text/plain'
  settings.codec.encrypt("#{confirmed_user.login} #{keygap}")
end

get '/invoice' do
  haml :invoice, layout: :layout, locals: merged(
    title: '@' + confirmed_user.login + '/invoice'
  )
end

get '/btc-refresh' do
  key = settings.config['blockchain']['key']
  callback = "https://wts.zold.io/btc-hook?id=#{confirmed_user.item.id}&key=#{key}"
  uri = 'https://api.blockchain.info/v2/receive?' + [
    "xpub=#{settings.config['blockchain']['xpub']}",
    "callback=#{CGI.escape(callback)}",
    "key=#{key}"
  ].join('&')
  res = Zold::Http.new(uri: uri).get
  raise "Can't create Bitcoin address for @#{confirmed_user.login}: #{res.status_line}" unless res.code == 200
  address = JSON.parse(res.body)['address']
  confirmed_user.item.save_btc(address)
  flash('/btc', 'A new unique BTC address is assigned to you')
end

get '/btc' do
  redirect '/btc-refresh' unless confirmed_user.item.btc?
  haml :btc, layout: :layout, locals: merged(
    title: '@' + confirmed_user.login + '/btc'
  )
end

# See https://www.blockchain.com/api/api_receive
get '/btc-hook' do
  return "Invalid key \"#{params[:key]}\"" unless params[:key] == settings.config['blockchain']['key']
  return "Not enough confirmations: #{params[:confirmations]}" unless params[:confirmations].to_i >= 3
  price = JSON.parse(Zold::Http.new(uri: 'https://blockchain.info/ticker').get.body)['USD']['15m']
  bitcoin = params[:value].to_f / 100_000_000
  usd = bitcoin / price
  ops(boss).pay(
    settings.config['rewards']['keygap'],
    Zold::Id.new(params[:id]),
    Zold::Amount.new(zld: usd),
    "BTC exchange of #{bitcoin.round(8)} BTC to #{usd} USD/ZLD at #{params[:transaction_hash]}"
  )
  log.info("Paid #{usd} to #{id} in exchange to #{amount} BTC")
  '*ok*'
end

get '/log' do
  content_type 'text/plain', charset: 'utf-8'
  log.content
end

get '/remotes' do
  haml :remotes, layout: :layout, locals: merged(
    title: '/remotes'
  )
end

get '/robots.txt' do
  content_type 'text/plain'
  "User-agent: *\nDisallow: /"
end

get '/version' do
  content_type 'text/plain'
  VERSION
end

get '/context' do
  content_type 'text/plain'
  context
end

get '/css/*.css' do
  content_type 'text/css', charset: 'utf-8'
  file = params[:splat].first
  sass file.to_sym, views: "#{settings.root}/assets/sass"
end

not_found do
  status 404
  content_type 'text/html', charset: 'utf-8'
  haml :not_found, layout: :layout, locals: merged(
    title: 'Page not found'
  )
end

error do
  status 503
  e = env['sinatra.error']
  if e.is_a?(UserError)
    flash('/', e.message)
  else
    Raven.capture_exception(e)
    haml(
      :error,
      layout: :layout,
      locals: merged(
        title: 'Error',
        error: Backtrace.new(e).to_s
      )
    )
  end
end

private

def flash(uri, msg)
  cookies[:flash_msg] = msg
  redirect uri
end

def context
  "#{request.ip} #{request.user_agent} #{VERSION}"
end

def merged(hash)
  out = @locals.merge(hash)
  out[:local_assigns] = out
  if cookies[:flash_msg]
    out[:flash_msg] = cookies[:flash_msg]
    cookies.delete(:flash_msg)
  end
  out
end

def log(user = @locals[:guser])
  TeeLog.new(
    settings.log,
    FileLog.new(File.join(settings.root, ".zold-wts/logs/#{user}"))
  )
end

def user(login = @locals[:guser])
  flash('/', 'You have to login first') unless login
  User.new(
    login, Item.new(login, settings.dynamo, log: log(login)),
    settings.wallets, log: log(login)
  )
end

def confirmed_user
  u = user
  flash('/confirm', 'You have to confirm your keygap') unless u.confirmed?
  u
end

def keygap
  params[:keygap] = params[:pass] if params[:pass]
  kg = @locals[:keygap].nil? ? params[:keygap] : @locals[:keygap]
  begin
    confirmed_user.item.key(kg).to_s
  rescue StandardError => e
    flash('/', "This doesn\'t seem to be a valid keygap: #{e.class.name}")
  end
  kg
end

def latch(login = @locals[:guser])
  File.join(settings.root, "latch/#{login}")
end

def ops(user = confirmed_user, async: true)
  network = ENV['RACK_ENV'] == 'test' ? 'test' : 'zold'
  ops = SafeOps.new(
    log(user.login),
    VersionedOps.new(
      log(user.login),
      LatchOps.new(
        latch(user.login),
        UpdateOps.new(
          Ops.new(
            user.item, user,
            settings.wallets,
            settings.remotes,
            settings.copies,
            log: log(user.login),
            network: network
          ),
          settings.remotes,
          log: log(user.login),
          network: network
        )
      )
    )
  )
  ops = AsyncOps.new(settings.pool, ops) if async
  ops
end

def pay_bonus
  boss = user(settings.config['rewards']['login'])
  return unless boss.item.exists?
  ops(boss).pay(
    settings.config['rewards']['keygap'], user.item.id,
    Zold::Amount.new(zld: 8.0), "WTS signup bonus to #{@locals[:guser]}"
  )
end

def pay_hosting_bonuses
  login = settings.config['rewards']['login']
  boss = user(login)
  return unless boss.item.exists?
  require 'zold/commands/remote'
  cmd = Zold::Remote.new(remotes: settings.remotes, log: log(login))
  cmd.run(%w[remote defaults])
  cmd.run(%w[remote update])
  winners = cmd.run(%w[remote elect --min-score=8 --max-winners=8])
  winners.each do |score|
    ops(boss).pay(
      settings.config['rewards']['keygap'],
      score.invoice,
      Zold::Amount.new(zld: 1.0 / winners.count),
      "Hosting bonus for #{score.host} #{score.port} #{score.value}"
    )
  end
end
