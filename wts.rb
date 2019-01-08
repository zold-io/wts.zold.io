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

require 'haml'
require 'geocoder'
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
require 'telepost'
require 'rack/ssl'
require 'get_process_mem'
require 'total'
require 'zold'
require 'zold/sync_wallets'
require 'zold/cached_wallets'
require_relative 'version'
require_relative 'objects/item'
require_relative 'objects/user'
require_relative 'objects/btc'
require_relative 'objects/bank'
require_relative 'objects/dynamo'
require_relative 'objects/hashes'
require_relative 'objects/user_error'
require_relative 'objects/ops'
require_relative 'objects/async_job'
require_relative 'objects/safe_job'
require_relative 'objects/update_job'
require_relative 'objects/clean_job'
require_relative 'objects/versioned_job'
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
      'exchange' => {
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
        'xpub' => '',
        'key' => ''
      },
      'telegram' => {
        'token' => '',
        'chat' => '111'
      },
      'coinbase' => {
        'key' => '',
        'secret' => '',
        'account' => ''
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
  set :show_exceptions, false
  set :dump_errors, false
  set :server_settings, timeout: 25
  set :dynamo, Dynamo.new(config).aws
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
  set :codec, GLogin::Codec.new(config['api_secret'])
  set :zache, Zache.new
  set :pool, Concurrent::FixedThreadPool.new(16, max_queue: 64, fallback_policy: :abort)
  set :log, Zold::Log::REGULAR.dup
  if settings.config['coinbase']['key'].empty?
    set :bank, Bank::Fake.new
  else
    set :bank, Bank.new(
      settings.config['coinbase']['key'],
      settings.config['coinbase']['secret'],
      settings.config['coinbase']['account']
    )
  end
  set :hashes, Hashes.new(settings.dynamo)
  if settings.config['blockchain']['xpub'].empty?
    set :btc, Btc::Fake.new
  else
    set :btc, Btc.new(
      settings.config['blockchain']['xpub'],
      settings.config['blockchain']['key'],
      log: settings.log
    )
  end
  if settings.config['telegram']['token'].empty?
    set :telepost, Telepost::Fake.new
  else
    set :telepost, Telepost.new(
      settings.config['telegram']['token'],
      chats: ['@zold_wts']
    )
    Thread.new do
      settings.telepost.run
    rescue StandardError => e
      Raven.capture_exception(e)
      settings.log.error(Backtrace.new(e))
    end
  end
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
  settings.telepost.spam(
    '[WTS](https://wts.zold.io) server software',
    "[#{VERSION}](https://github.com/zold-io/wts.zold.io/releases/tag/#{VERSION})",
    'has been deployed and starts to work.',
    "Zold version is [#{Zold::VERSION}](https://rubygems.org/gems/zold/versions/#{Zold::VERSION}),",
    "protocol is `#{Zold::PROTOCOL}`."
  )
end

before '/*' do
  @locals = {
    ver: VERSION,
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
  header = request.env['HTTP_X_ZOLD_WTS']
  if header
    begin
      login, keygap = settings.codec.decrypt(header).split(' ')
      @locals[:guser] = login
      @locals[:keygap] = keygap
      settings.log.info(
        "HTTP authentication header of @#{login} detected \
from #{request.ip} with keygap of #{keygap.length} chars"
      )
    rescue OpenSSL::Cipher::CipherError => _
      error 400
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
  unless user.item.exists?
    flash('/create', 'Time to create your wallet') unless File.exist?(latch(user.login))
    return haml :busy, layout: :layout, locals: merged(
      title: '@' + @locals[:guser] + '/busy'
    )
  end
  flash('/confirm', 'Time to save your keygap') unless user.confirmed?
  haml :home, layout: :layout, locals: merged(
    title: '@' + @locals[:guser],
    start: params[:start] ? Time.parse(params[:start]) : nil
  )
end

get '/create' do
  job do
    user.create
    ops.push
    settings.telepost.spam(
      "The user [@#{user.login}](https://github.com/#{user.login})",
      "created a new wallet [#{user.item.id}](http://www.zold.io/ledger.html?wallet=#{user.item.id})",
      "from `#{request.ip}` (#{country})."
    )
    known = Zold::Http.new(uri: 'https://www.0crat.com/known/' + user.login).get
    if known.code == 200
      boss = user(settings.config['rewards']['login'])
      amount = Zold::Amount.new(zld: 0.256)
      job(boss) do
        ops(boss).pay(
          settings.config['rewards']['keygap'], user.item.id,
          amount, "WTS signup bonus to #{user.login}"
        )
        settings.telepost.spam(
          "Sign-up bonus of #{amount} has been sent",
          "to [@#{user.login}](https://github.com/#{user.login})",
          "from `#{request.ip}` (#{country}),",
          "to their wallet [#{user.item.id}](http://www.zold.io/ledger.html?wallet=#{user.item.id})",
          "from our wallet [#{boss.item.id}](http://www.zold.io/ledger.html?wallet=#{boss.item.id})",
          "of [#{boss.login}](https://github.com/#{boss.login})",
          "with the remaining balance of #{boss.wallet(&:balance)} (#{boss.wallet(&:txns).count}t)."
        )
      end
    else
      settings.telepost.spam(
        "Sign-up bonus won't be sent to",
        "[@#{user.login}](https://github.com/#{user.login})",
        "from `#{request.ip}` (#{country})",
        "with the wallet [#{user.item.id}](http://www.zold.io/ledger.html?wallet=#{user.item.id})",
        "because this user is not [known](https://www.0crat.com/known/#{user.login}) to Zerocracy."
      )
    end
  end
  flash('/', 'Your wallet is created and will be pushed soon')
end

get '/confirm' do
  raise UserError, 'You have done this already, your keygap has been generated' if user.confirmed?
  haml :confirm, layout: :layout, locals: merged(
    title: '@' + user.login + '/keygap'
  )
end

get '/do-confirm' do
  raise UserError, 'You have done this already, your keygap has been generated' if user.confirmed?
  user.confirm(params[:keygap])
  flash('/', 'The account has been confirmed')
end

get '/keygap' do
  raise UserError, 'We don\'t have it in the database anymore' if user.item.wiped?
  content_type 'text/plain'
  user.item.keygap
end

get '/pay' do
  haml :pay, layout: :layout, locals: merged(
    title: '@' + confirmed_user.login + '/pay'
  )
end

post '/do-pay' do
  raise UserError, 'Parameter "bnf" is not provided' if params[:bnf].nil?
  raise UserError, 'Parameter "amount" is not provided' if params[:amount].nil?
  raise UserError, 'Parameter "details" is not provided' if params[:details].nil?
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
  job do
    ops.pay(keygap, bnf, amount, details)
    settings.telepost.spam(
      "Payment sent by [@#{user.login}](https://github.com/#{user.login})",
      "from [#{user.item.id}](http://www.zold.io/ledger.html?wallet=#{user.item.id})",
      "with the balance of #{user.wallet(&:balance)}",
      "to [#{bnf}](http://www.zold.io/ledger.html?wallet=#{bnf})",
      "for #{amount} from `#{request.ip}` (#{country}):",
      "\"#{details}\"."
    )
  end
  flash('/', "Payment has been sent to #{bnf} for #{amount}")
end

get '/pull' do
  job { ops.pull }
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
  content_type 'text/plain'
  confirmed_user.wallet(&:balance).to_i
end

get '/find' do
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

get '/id_rsa' do
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

get '/btc' do
  unless confirmed_user.item.btc?
    address = settings.btc.create(confirmed_user.login)
    confirmed_user.item.save_btc(address)
    settings.telepost.spam(
      "New Bitcoin address assigned to [@#{user.login}](https://github.com/#{user.login})",
      "from `#{request.ip}` (#{country}):",
      "[#{address[0..8]}](https://www.blockchain.com/btc/address/#{address})."
    )
  end
  haml :btc, layout: :layout, locals: merged(
    title: '@' + confirmed_user.login + '/btc'
  )
end

# See https://www.blockchain.com/api/api_receive
get '/btc-hook' do
  return '*ok*' if params[:confirmations].to_i > 64
  raise UserError, 'Zold user name is not provided' if params[:zold_user].nil?
  raise UserError, 'Tx hash is not provided' if params[:transaction_hash].nil?
  raise UserError, 'Tx value is not provided' if params[:value].nil?
  hash = params[:transaction_hash]
  bnf = user(params[:zold_user])
  raise UserError, "There is no user @#{bnf.login}" unless bnf.item.exists?
  raise UserError, "The user @#{bnf.login} is not confirmed" unless bnf.confirmed?
  raise UserError, "The user @#{bnf.login} doesn't have BTC address" unless bnf.item.btc?
  address = bnf.item.btc
  satoshi = params[:value].to_i
  raise UserError, "Tx #{hash}/#{satoshi}/#{bnf.item.btc} not found" unless settings.btc.exists?(hash, satoshi, address)
  raise UserError, "BTC hash #{hash} has already been paid" if settings.hashes.seen?(hash)
  bitcoin = satoshi.to_f / 100_000_000
  zld = Zold::Amount.new(zld: bitcoin / rate * (1 - fee))
  boss = user(settings.config['exchange']['login'])
  job(boss) do
    ops(boss).pay(
      settings.config['exchange']['keygap'],
      bnf.item.id,
      zld,
      "BTC exchange of #{bitcoin.round(8)} at #{hash}, rate is #{rate}, fee is #{fee}"
    )
    settings.hashes.add(hash, bnf.login, bnf.item.id)
    settings.telepost.spam(
      "In: #{bitcoin} BTC [exchanged](https://blog.zold.io/2018/12/09/btc-to-zld.html) to #{zld}",
      "by [@#{bnf.login}](https://github.com/#{bnf.login}) from `#{request.ip}` (#{country})",
      "in [#{hash[0..8]}](https://www.blockchain.com/btc/tx/#{hash})",
      "via [#{address[0..8]}](https://www.blockchain.com/btc/address/#{address}),",
      "to the wallet [#{bnf.item.id}](http://www.zold.io/ledger.html?wallet=#{bnf.item.id})",
      "with the balance of #{bnf.wallet(&:balance)};",
      "BTC price at the moment of exchange was [$#{settings.btc.price}](https://blockchain.info/ticker);",
      "the payer is [@#{boss.login}](https://github.com/#{boss.login}) with the wallet",
      "[#{boss.item.id}](http://www.zold.io/ledger.html?wallet=#{boss.item.id}),",
      "the remaining balance is #{boss.wallet(&:balance)} (#{boss.wallet(&:txns).count}t)."
    )
  end
  '*ok*'
end

post '/do-sell' do
  raise UserError, 'Amoung is not provided' if params[:amount].nil?
  raise UserError, 'Bitcoin address is not provided' if params[:btc].nil?
  raise UserError, 'Keygap is not provided' if params[:keygap].nil?
  amount = Zold::Amount.new(zld: params[:amount].to_f)
  raise UserError, "The amount #{amount} is too large for us now" if amount > Zold::Amount.new(zld: 4.0)
  address = params[:btc]
  raise UserError, "You don't have enough to send #{amount}" if confirmed_user.wallet(&:balance) < amount
  if user.wallet(&:txns).find { |t| t.amount.negative? && t.date > Time.now - 60 * 60 * 24 }
    raise UserError, 'At the moment we can send only one payment per day, sorry' unless user.login == 'yegor256'
  end
  price = settings.btc.price
  bitcoin = (amount.to_zld(8).to_f * rate * (1 - fee)).round(10)
  usd = bitcoin * price
  boss = user(settings.config['exchange']['login'])
  job do
    ops.pay(
      params[:keygap],
      boss.item.id,
      amount,
      "ZLD exchange to #{bitcoin} BTC at #{address}, rate is #{rate}, fee is #{fee}"
    )
    settings.bank.send(
      address, usd,
      "Exchange of #{amount.to_zld(8)} by @#{user.login} to #{user.item.id}, rate is #{rate}, fee is #{fee}"
    )
    settings.telepost.spam(
      "Out: #{amount} [exchanged](https://blog.zold.io/2018/12/09/btc-to-zld.html) to #{bitcoin} BTC",
      "by [@#{user.login}](https://github.com/#{user.login}) from `#{request.ip}` (#{country})",
      "from the wallet [#{user.item.id}](http://www.zold.io/ledger.html?wallet=#{user.item.id})",
      "with the balance of #{user.wallet(&:balance)}",
      "to bitcoin address [#{address[0..8]}](https://www.blockchain.com/btc/address/#{address});",
      "BTC price at the time of exchange was [$#{price}](https://blockchain.info/ticker);",
      "our bitcoin wallet still has #{settings.bank.balance} BTC;",
      "zolds were deposited to [#{boss.item.id}](http://www.zold.io/ledger.html?wallet=#{boss.item.id})",
      "of [#{boss.login}](https://github.com/#{boss.login}),",
      "the balance is #{boss.wallet(&:balance)} (#{boss.wallet(&:txns).count}t)."
    )
  end
  flash('/btc', "We took #{amount} from your wallet and sent you #{bitcoin} BTC")
end

get '/log' do
  content_type 'text/plain', charset: 'utf-8'
  log.content + "\n\n\n" + [
    'If you see any errors here, which you don\'t understand,',
    'please submit an issue to our GitHub repository here and copy the entire log over there:',
    'https://github.com/zold-io/wts.zold.io/issues;',
    'we need your feedback in order to make our system better;',
    'you can also discuss it in our Telegram group: https://t.me/zold_io.'
  ].join(' ')
end

get '/remotes' do
  haml :remotes, layout: :layout, locals: merged(
    title: '/remotes'
  )
end

get '/rate' do
  unless settings.zache.exists?(:rate)
    boss = user(settings.config['exchange']['login'])
    job(boss) do
      ops(boss).pull
      require 'zold/commands/pull'
      Zold::Pull.new(
        wallets: settings.wallets, remotes: settings.remotes, copies: settings.copies, log: settings.log
      ).run(['pull', Zold::Id::ROOT.to_s, "--network=#{network}"])
      hash = {
        bank: settings.bank.balance,
        boss: settings.wallets.acq(boss.item.id, &:balance),
        root: settings.wallets.acq(Zold::Id::ROOT, &:balance) * -1
      }
      hash[:rate] = hash[:bank] / (hash[:root] - hash[:boss]).to_f
      hash[:deficit] = (hash[:root] - hash[:boss]).to_f / rate - hash[:bank]
      settings.zache.put(:rate, hash, lifetime: 10 * 60)
    end
  end
  flash('/', 'Still working on it, come back in a few seconds') unless settings.zache.exists?(:rate)
  haml :rate, layout: :layout, locals: merged(
    title: '/rate',
    formula: settings.zache.get(:rate, dirty: true)
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
    settings.log.error(e.message)
    # settings.log.error(Backtrace.new(e))
    body(Backtrace.new(e).to_s)
    headers['X-Zold-Error'] = e.message[0..256]
    flash('/', e.message, color: 'darkred')
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

def rate
  0.00025
end

def fee
  0.08
end

def country
  country = Geocoder.search(request.ip).first
  country.nil? ? '??' : country.country.to_s
end

def flash(uri, msg, color: 'darkgreen')
  cookies[:flash_msg] = msg
  cookies[:flash_color] = color
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
  out[:flash_color] = cookies[:flash_color] || 'darkgreen'
  cookies.delete(:flash_color)
  out
end

def log(u = user.login)
  TeeLog.new(
    settings.log,
    FileLog.new(File.join(settings.root, ".zold-wts/logs/#{u}"))
  )
end

def user(login = @locals[:guser])
  raise UserError, 'You have to login first' unless login
  User.new(
    login, Item.new(login, settings.dynamo, log: log(login)),
    settings.wallets, log: log(login)
  )
end

def confirmed_user(login = @locals[:guser])
  u = user(login)
  raise UserError, "You @#{login} have to confirm your keygap first" unless u.confirmed?
  u
end

def keygap
  params[:keygap] = params[:pass] if params[:pass]
  kg = @locals[:keygap].nil? ? params[:keygap] : @locals[:keygap]
  raise UserError, 'Keygap is required' if kg.nil?
  begin
    confirmed_user.item.key(kg).to_s
  rescue StandardError => e
    raise UserError, "This doesn\'t seem to be a valid keygap: #{e.class.name}"
  end
  kg
end

def latch(login = @locals[:guser])
  File.join(settings.root, "latch/#{login}")
end

def network
  ENV['RACK_ENV'] == 'test' ? 'test' : 'zold'
end

def ops(u = user)
  Ops.new(
    u.item,
    u,
    settings.wallets,
    settings.remotes,
    settings.copies,
    log: log(u.login),
    network: network
  )
end

def job(u = user)
  lg = log(u.login)
  job = SafeJob.new(
    VersionedJob.new(
      CleanJob.new(
        UpdateJob.new(
          proc { yield },
          settings.remotes,
          log: lg,
          network: network
        ),
        settings.wallets,
        u.item,
        log: lg
      ),
      log: lg
    ),
    log: lg
  )
  job = AsyncJob.new(job, settings.pool, latch(u.login)) unless ENV['RACK_ENV'] == 'test'
  job.call
end

def pay_hosting_bonuses
  login = settings.config['rewards']['login']
  boss = user(login)
  return unless boss.item.exists?
  job(boss) do
    require 'zold/commands/remote'
    cmd = Zold::Remote.new(remotes: settings.remotes, log: log(login))
    winners = cmd.run(%w[remote elect --min-score=8 --max-winners=8])
    total = Zold::Amount.new(zld: 1.0)
    winners.each do |score|
      ops(boss).pay(
        settings.config['rewards']['keygap'],
        score.invoice,
        total / winners.count,
        "Hosting bonus for #{score.host} #{score.port} #{score.value}"
      )
    end
    if winners.empty?
      settings.telepost.spam(
        'Attention, no hosting [bonuses](https://blog.zold.io/2018/08/14/hosting-bonuses.html)',
        'were paid because no nodes were found,',
        "which would deserve that, among [#{settings.remotes.all.count} visible](https://wts.zold.io/remotes);",
        'something is wrong with the network,',
        'check this [health](http://www.zold.io/health.html) page!'
      )
    else
      settings.telepost.spam(
        'Hosting [bonus](https://blog.zold.io/2018/08/14/hosting-bonuses.html)',
        "of #{total} has been distributed among #{winners.count} wallets",
        '[visible](https://wts.zold.io/remotes) to us at the moment,',
        'among [others](http://www.zold.io/health.html):',
        winners.map do |s|
          "[#{s.host}:#{s.port}](http://www.zold.io/ledger.html?wallet=#{s.invoice.split('@')[1]})/#{s.value}"
        end.join(', ') + ';',
        "the payer is [@#{boss.login}](https://github.com/#{boss.login}) with the wallet",
        "[#{boss.item.id}](http://www.zold.io/ledger.html?wallet=#{boss.item.id}),",
        "the remaining balance is #{boss.wallet(&:balance)} (#{boss.wallet(&:txns).count}t)."
      )
    end
  end
end
