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

require 'aws-sdk-sns'
require 'haml'
require 'geocoder'
require 'sinatra'
require 'sinatra/cookies'
require 'sass'
require 'securerandom'
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
require 'zold/hands'
require 'zold/sync_wallets'
require 'zold/cached_wallets'
require_relative 'version'
require_relative 'objects/callbacks'
require_relative 'objects/payables'
require_relative 'objects/smss'
require_relative 'objects/payouts'
require_relative 'objects/daemon'
require_relative 'objects/ticks'
require_relative 'objects/graph'
require_relative 'objects/item'
require_relative 'objects/items'
require_relative 'objects/user'
require_relative 'objects/btc'
require_relative 'objects/bank'
require_relative 'objects/dynamo'
require_relative 'objects/hashes'
require_relative 'objects/user_error'
require_relative 'objects/ops'
require_relative 'objects/gl'
require_relative 'objects/pgsql'
require_relative 'objects/async_job'
require_relative 'objects/safe_job'
require_relative 'objects/update_job'
require_relative 'objects/clean_job'
require_relative 'objects/zache_job'
require_relative 'objects/versioned_job'
require_relative 'objects/file_log'
require_relative 'objects/tee_log'

if ENV['RACK_ENV'] != 'test'
  require 'rack/ssl'
  use Rack::SSL
end

configure do
  Zold::Hands.start
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
        'region' => '?',
        'key' => '?',
        'secret' => '?'
      },
      'pgsql' => {
        'host' => 'localhost',
        'port' => 0,
        'user' => 'test',
        'dbname' => 'test',
        'password' => 'test'
      },
      'sns' => {
        'region' => '?',
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
  set :raise_errors, false
  set :dump_errors, false
  set :server_settings, timeout: 25
  set :log, Zold::Log::REGULAR.dup
  set :dynamo, Dynamo.new(config).aws
  set :items, Items.new(settings.dynamo, log: settings.log)
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
  set :pgsql, Pgsql.new(
    host: settings.config['pgsql']['host'],
    port: settings.config['pgsql']['port'],
    dbname: settings.config['pgsql']['dbname'],
    user: settings.config['pgsql']['user'],
    password: settings.config['pgsql']['password']
  ).start(1)
  set :gl, Gl.new(settings.pgsql, log: settings.log)
  set :payables, Payables.new(settings.pgsql, settings.remotes, log: settings.log)
  set :payouts, Payouts.new(settings.pgsql, log: settings.log)
  set :callbacks, Callbacks.new(settings.pgsql, log: settings.log)
  set :codec, GLogin::Codec.new(config['api_secret'])
  set :zache, Zache.new(dirty: true)
  set :jobs, Zache.new
  set :ticks, Ticks.new(settings.dynamo, log: settings.log)
  set :pool, Concurrent::FixedThreadPool.new(16, max_queue: 64, fallback_policy: :abort)
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
  set :smss, Smss.new(
    settings.pgsql,
    Aws::SNS::Client.new(
      region: settings.config['sns']['region'],
      access_key_id: settings.config['sns']['key'],
      secret_access_key: settings.config['sns']['secret']
    ),
    log: settings.log
  )
  if settings.config['telegram']['token'].empty?
    set :telepost, Telepost::Fake.new
  else
    set :telepost, Telepost.new(
      settings.config['telegram']['token'],
      chats: ['@zold_wts']
    )
    Daemon.new(settings.log).run(0) do
      settings.telepost.run
    end
  end
  Daemon.new(settings.log).run(10) do
    login = settings.config['rewards']['login']
    boss = user(login)
    job(boss) { pay_hosting_bonuses(boss) } if boss.item.exists?
  end
  Daemon.new(settings.log).run do
    settings.gl.scan(settings.remotes) do |t|
      settings.log.info("A new transaction added to the General Ledger \
for #{t[:amount].to_zld(6)} from #{t[:source]} to #{t[:target]} with details \"#{t[:details]}\" \
and dated of #{t[:date].utc.iso8601}")
      settings.callbacks.match(t[:target], t[:prefix], t[:details])
    end
  end
  Daemon.new(settings.log).run(5) do
    settings.callbacks.ping do |login, id, pfx, regexp|
      ops(user(login)).pull(id)
      settings.wallets.acq(id) do |wallet|
        wallet.txns.select do |t|
          t.prefix == pfx && regexp.match?(t.details)
        end
      end
    end
  end
  Daemon.new(settings.log).run(10) do
    settings.payables.discover
    settings.payables.update
  end
  settings.telepost.spam(
    '[WTS](https://wts.zold.io) server software',
    "[#{VERSION}](https://github.com/zold-io/wts.zold.io/releases/tag/#{VERSION})",
    'has been deployed and starts to work;',
    "Zold version is [#{Zold::VERSION}](https://rubygems.org/gems/zold/versions/#{Zold::VERSION}),",
    "the protocol is `#{Zold::PROTOCOL}`"
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
  header = request.env['HTTP_X_ZOLD_WTS'] || cookies[:wts] || nil
  if header
    login, token = header.strip.split('-', 2)
    unless user(login).item.exists?
      settings.log.info("API login: User #{login} is absent")
      return
    end
    unless user(login).item.token == token
      settings.log.info("Invalid token #{token.inspect} of #{login}")
      return
    end
    @locals[:guser] = login.downcase
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
  cookies.delete(:wts)
  flash('/', 'You have been logged out')
end

get '/' do
  redirect '/home' if @locals[:guser]
  haml :index, layout: :layout, locals: merged(
    page_title: 'wts'
  )
end

get '/mobile_send' do
  redirect '/home' if @locals[:guser]
  haml :mobile_send, layout: :layout, locals: merged(
    page_title: '/mobile'
  )
end

get '/mobile_token' do
  redirect '/home' if @locals[:guser]
  haml :mobile_token, layout: :layout, locals: merged(
    page_title: '/token',
    phone: params[:phone]
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

get '/create' do
  job do
    log.info('Creating a new wallet by /create request...')
    user.create
    ops.push
    settings.telepost.spam(
      "The user #{title_md}",
      "created a new wallet [#{user.item.id}](http://www.zold.io/ledger.html?wallet=#{user.item.id})",
      "from #{anon_ip}"
    )
    if known?
      boss = user(settings.config['rewards']['login'])
      amount = Zold::Amount.new(zld: 0.256)
      job(boss) do
        if boss.wallet(&:balance) < amount
          settings.telepost.spam(
            "A sign-up bonus of #{amount} can't be sent",
            "to #{title_md} from #{anon_ip}",
            "to their wallet [#{user.item.id}](http://www.zold.io/ledger.html?wallet=#{user.item.id})",
            "from our wallet [#{boss.item.id}](http://www.zold.io/ledger.html?wallet=#{boss.item.id})",
            "of [#{boss.login}](https://github.com/#{boss.login})",
            "because there is not enough found, only #{boss.wallet(&:balance)} left"
          )
        else
          ops(boss).pay(
            settings.config['rewards']['keygap'], user.item.id,
            amount, "WTS signup bonus to #{user.login}"
          )
          settings.telepost.spam(
            "The sign-up bonus of #{amount} has been sent",
            "to #{title_md} from #{anon_ip},",
            "to their wallet [#{user.item.id}](http://www.zold.io/ledger.html?wallet=#{user.item.id})",
            "from our wallet [#{boss.item.id}](http://www.zold.io/ledger.html?wallet=#{boss.item.id})",
            "of [#{boss.login}](https://github.com/#{boss.login})",
            "with the remaining balance of #{boss.wallet(&:balance)} (#{boss.wallet(&:txns).count}t)"
          )
        end
      end
    else
      settings.telepost.spam(
        "A sign-up bonus won't be sent to #{title_md} from #{anon_ip}",
        "with the wallet [#{user.item.id}](http://www.zold.io/ledger.html?wallet=#{user.item.id})",
        "because this user is not [known](https://www.0crat.com/known/#{user.login}) to Zerocracy"
      )
    end
  end
  flash('/', 'Your wallet is created and will be pushed soon')
end

get '/confirm' do
  raise UserError, 'You have done this already, your keygap has been generated' if user.confirmed?
  haml :confirm, layout: :layout, locals: merged(
    page_title: title('keygap')
  )
end

get '/confirmed' do
  content_type 'text/plain'
  user.confirmed? ? 'yes' : 'no'
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
    page_title: title('pay')
  )
end

post '/do-pay' do
  raise UserError, 'Parameter "bnf" is not provided' if params[:bnf].nil?
  raise UserError, 'Parameter "amount" is not provided' if params[:amount].nil?
  raise UserError, 'Parameter "details" is not provided' if params[:details].nil?
  if /^[a-f0-9]{16}$/.match?(params[:bnf])
    bnf = Zold::Id.new(params[:bnf])
    raise UserError, 'You can\'t pay yourself' if bnf == user.item.id
  elsif /^[a-zA-Z0-9]+@[a-f0-9]{16}$/.match?(params[:bnf])
    bnf = params[:bnf]
    raise UserError, 'You can\'t pay yourself' if bnf.split('@')[1] == user.item.id.to_s
  elsif /^\\+[0-9]+$/.match?(params[:bnf])
    friend = user(params[:bnf][0..32].to_i.to_s)
    raise UserError, 'The user with this mobile phone is not registered yet' unless friend.item.exists?
    bnf = friend.item.id
  else
    login = params[:bnf].strip.downcase.gsub(/^@/, '')
    raise UserError, "Invalid GitHub user name: #{params[:bnf].inspect}" unless login =~ /^[a-z0-9-]{3,32}$/
    raise UserError, 'You can\'t pay yourself' if login == user.login
    friend = user(login)
    unless friend.item.exists?
      friend.create
      ops(friend).push
    end
    bnf = friend.item.id
  end
  amount = Zold::Amount.new(zld: params[:amount].to_f)
  details = params[:details]
  raise UserError, "Invalid details \"#{details}\"" unless details =~ %r{^[a-zA-Z0-9\ @!?*_\-.:,'/]+$}
  headers['X-Zold-Job'] = job do
    log.info("Sending #{amount} to #{bnf}...")
    ops.pay(keygap, bnf, amount, details)
    settings.telepost.spam(
      "Payment sent by #{title_md}",
      "from [#{user.item.id}](http://www.zold.io/ledger.html?wallet=#{user.item.id})",
      "with the balance of #{user.wallet(&:balance)}",
      "to [#{bnf}](http://www.zold.io/ledger.html?wallet=#{bnf})",
      "for #{amount} from #{anon_ip}:",
      "\"#{details}\""
    )
  end
  flash('/', "Payment has been sent to #{bnf} for #{amount}")
end

get '/pull' do
  headers['X-Zold-Job'] = job do
    log.info("Pulling wallet #{user.item.id} via /pull...")
    ops.pull
  end
  flash('/', "Your wallet #{user.item.id} will be pulled soon")
end

get '/restart' do
  haml :restart, layout: :layout, locals: merged(
    page_title: title('restart')
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
  response.headers['Content-Type'] = 'application/octet-stream'
  response.headers['Content-Disposition'] = "attachment; filename='id_rsa'"
  confirmed_user.item.key(keygap).to_s
end

get '/api' do
  haml :api, layout: :layout, locals: merged(
    page_title: title('api')
  )
end

get '/api-reset' do
  confirmed_user.item.token_reset
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
  prefix = inv.split('@')[0]
  content_type 'application/json'
  JSON.pretty_generate(prefix: prefix, invoice: inv)
end

get '/callbacks' do
  haml :callbacks, layout: :layout, locals: merged(
    page_title: title('callbacks'),
    callbacks: settings.callbacks
  )
end

get '/null' do
  content_type 'text/plain'
  'OK'
end

get '/wait-for' do
  wallet = params[:wallet]
  raise UserError, 'The parameter "wallet" is mandatory' if wallet.nil?
  prefix = params[:prefix]
  raise UserError, 'The parameter "prefix" is mandatory' if prefix.nil?
  regexp = params[:regexp] ? Regexp.new(params[:regexp]) : /^.*$/
  uri = URI(params[:uri])
  raise UserError, 'The parameter "uri" is mandatory' if uri.nil?
  id = settings.callbacks.add(
    user.login, Zold::Id.new(wallet), prefix, regexp, uri,
    params[:token] || 'none'
  )
  settings.telepost.spam(
    "New callback no.#{id} created by #{title_md} from #{anon_ip}",
    "for the wallet [#{wallet}](http://www.zold.io/ledger.html?wallet=#{wallet}),",
    "prefix `#{prefix}`, and regular expression `#{regexp}`"
  )
  content_type 'text/plain'
  id.to_s
end

get '/migrate' do
  haml :migrate, layout: :layout, locals: merged(
    page_title: title('migrate')
  )
end

get '/do-migrate' do
  headers['X-Zold-Job'] = job do
    origin = user.item.id
    ops.migrate(keygap)
    settings.telepost.spam(
      "The wallet [#{origin}](http://www.zold.io/ledger.html?wallet=#{origin})",
      "with #{settings.wallets.acq(origin, &:txns).count} transactions",
      "and #{user.wallet(&:balance)}",
      "has been migrated to a new wallet [#{user.item.id}](http://www.zold.io/ledger.html?wallet=#{user.item.id})",
      "by #{title_md} from #{anon_ip}"
    )
  end
  flash('/', 'You got a new wallet ID, your funds will be transferred soon...')
end

get '/btc' do
  confirmed_user.item.btc do
    address = settings.btc.create
    settings.telepost.spam(
      'New Bitcoin address acquired',
      "[#{address[0..8]}](https://www.blockchain.com/btc/address/#{address})",
      "by request of #{title_md} from #{anon_ip};",
      "Blockchain.com gap is #{settings.btc.gap};",
      settings.btc.to_s
    )
    address
  end
  headers['X-Zold-BtcAddress'] = confirmed_user.item.btc
  haml :btc, layout: :layout, locals: merged(
    page_title: title('buy+sell'),
    gap: settings.zache.get(:gap, lifetime: 60) { settings.btc.gap }
  )
end

# See https://www.blockchain.com/api/api_receive
get '/btc-hook' do
  settings.log.info("Blockchain.com hook arrived: #{params}")
  raise UserError, 'Confirmations is not provided' if params[:confirmations].nil?
  confirmations = params[:confirmations].to_i
  raise UserError, 'Address is not provided' if params[:address].nil?
  address = params[:address]
  raise UserError, 'Tx hash is not provided' if params[:transaction_hash].nil?
  hash = params[:transaction_hash]
  return '*ok*' if settings.hashes.seen?(hash)
  raise UserError, 'Tx value is not provided' if params[:value].nil?
  satoshi = params[:value].to_i
  bitcoin = (satoshi.to_f / 100_000_000).round(8)
  zld = Zold::Amount.new(zld: bitcoin / rate)
  bnf = user(settings.items.find_by_btc(address).login)
  raise UserError, "The user '#{bnf.login}' is not confirmed" unless bnf.confirmed?
  if confirmations.zero?
    bnf.item.btc_arrived
    settings.telepost.spam(
      "Bitcoin transaction arrived for #{bitcoin} BTC",
      "in [#{hash[0..8]}](https://www.blockchain.com/btc/tx/#{hash})",
      "and was identified as belonging to #{title_md(bnf)},",
      "#{zld} will be deposited to the wallet",
      "[#{bnf.item.id}](http://www.zold.io/ledger.html?wallet=#{bnf.item.id})",
      "once we see enough confirmations, now it's #{confirmations} (may take up to an hour!)"
    )
  end
  unless settings.btc.exists?(hash, satoshi, address, confirmations)
    raise UserError, "Tx #{hash}/#{satoshi}/#{bnf.item.btc} not found yet or is not yet confirmed enough"
  end
  boss = user(settings.config['exchange']['login'])
  job(boss) do
    if settings.hashes.seen?(hash)
      settings.log.info("A duplicate notification from Blockchain about #{bitcoin} bitcoins \
arrival to #{address}, for #{bnf.login}; we ignore it.")
    else
      log(bnf).info("Accepting #{bitcoin} bitcoins from #{address}...")
      ops(boss, log: log(bnf)).pay(
        settings.config['exchange']['keygap'],
        bnf.item.id,
        zld,
        "BTC exchange of #{bitcoin} at #{hash[0..8]}, rate is #{rate}"
      )
      bnf.item.destroy_btc
      settings.hashes.add(hash, bnf.login, bnf.item.id)
      settings.telepost.spam(
        "In: #{bitcoin} BTC [exchanged](https://blog.zold.io/2018/12/09/btc-to-zld.html) to #{zld}",
        "by #{title_md(bnf)}",
        "in [#{hash[0..8]}](https://www.blockchain.com/btc/tx/#{hash})",
        "(#{params[:confirmations]} confirmations)",
        "via [#{address[0..8]}](https://www.blockchain.com/btc/address/#{address}),",
        "to the wallet [#{bnf.item.id}](http://www.zold.io/ledger.html?wallet=#{bnf.item.id})",
        "with the balance of #{bnf.wallet(&:balance)};",
        "the gap of Blockchain.com is #{settings.btc.gap};",
        "BTC price at the moment of exchange was [$#{settings.btc.price}](https://blockchain.info/ticker);",
        "the payer is #{title_md(boss)} with the wallet",
        "[#{boss.item.id}](http://www.zold.io/ledger.html?wallet=#{boss.item.id}),",
        "the remaining balance is #{boss.wallet(&:balance)} (#{boss.wallet(&:txns).count}t)"
      )
    end
  end
  'Thanks!'
end

get '/zache-flush' do
  raise UserError, 'You are not allowed to see this' unless user.login == 'yegor256'
  settings.zache.remove_all
  content_type 'text/plain', charset: 'utf-8'
  'done'
end

get '/queue' do
  raise UserError, 'You are not allowed to see this' unless user.login == 'yegor256'
  content_type 'text/plain', charset: 'utf-8'
  settings.items.all.map do |i|
    "#{i['login']} #{Zold::Age.new(Time.at(i['assigned']))} #{i['btc']} A=#{i['active'].to_i}"
  end.join("\n")
end

get '/queue-clean' do
  raise UserError, 'You are not allowed to see this' unless user.login == 'yegor256'
  content_type 'text/plain', charset: 'utf-8'
  settings.items.all.map do |i|
    next if params[:login] && i['login'] != params[:login]
    user(i['login']).item.destroy_btc
    "#{i['login']} #{Zold::Age.new(Time.at(i['assigned']))} #{i['btc']}: destroyed"
  end.compact.join("\n")
end

get '/payouts' do
  haml :payouts, layout: :layout, locals: merged(
    page_title: title('payouts'),
    payouts: settings.payouts
  )
end

post '/do-sell' do
  raise UserError, 'Amount is not provided' if params[:amount].nil?
  raise UserError, 'Bitcoin address is not provided' if params[:btc].nil?
  raise UserError, 'Keygap is not provided' if params[:keygap].nil?
  amount = Zold::Amount.new(zld: params[:amount].to_f)
  raise UserError, "The amount #{amount} is too large for us now" if amount > sell_limit
  address = params[:btc]
  raise UserError, "Bitcoin address is not valid: #{address.inspect}" unless address =~ /^[a-zA-Z0-9]+$/
  raise UserError, 'Bitcoin address must start with 1, 3 or bc1' unless address =~ /^(1|3|bc1)/
  raise UserError, "You don't have enough to send #{amount}" if confirmed_user.wallet(&:balance) < amount
  unless settings.payouts.allowed?(user.login, amount)
    raise UserError, "With #{amount} you are going over your limits, sorry"
  end
  price = settings.btc.price
  bitcoin = (amount.to_zld(8).to_f * rate).round(8)
  usd = bitcoin * price
  boss = user(settings.config['exchange']['login'])
  rewards = user(settings.config['rewards']['login'])
  job do
    log.info("Sending #{bitcoin} bitcoins to #{address}...")
    ops.pay(
      keygap,
      boss.item.id,
      amount * (1 - fee),
      "ZLD exchange to #{bitcoin} BTC at #{address}, rate is #{rate}, fee is #{fee}"
    )
    ops.pay(
      keygap,
      rewards.item.id,
      amount * fee,
      "Fee for exchange of #{bitcoin} BTC at #{address}, rate is #{rate}, fee is #{fee}"
    )
    settings.bank.send(
      address,
      (usd * (1 - fee)).round(2),
      "Exchange of #{amount.to_zld(8)} by #{title} to #{user.item.id}, rate is #{rate}, fee is #{fee}"
    )
    settings.payouts.add(
      user.login, user.item.id, amount,
      "#{bitcoin} BTC sent to #{address}, the price was $#{price.round}/BTC, the fee was #{(fee * 100).round(2)}%"
    )
    settings.telepost.spam(
      "Out: #{amount} [exchanged](https://blog.zold.io/2018/12/09/btc-to-zld.html) to #{bitcoin} BTC",
      "by #{title_md} from #{anon_ip}",
      "from the wallet [#{user.item.id}](http://www.zold.io/ledger.html?wallet=#{user.item.id})",
      "with the balance of #{user.wallet(&:balance)}",
      "to bitcoin address [#{address[0..8]}](https://www.blockchain.com/btc/address/#{address});",
      "BTC price at the time of exchange was [$#{price.round}](https://blockchain.info/ticker);",
      "our bitcoin wallet still has #{settings.bank.balance.round(3)} BTC",
      "(worth about $#{(settings.bank.balance * price).round});",
      "zolds were deposited to [#{boss.item.id}](http://www.zold.io/ledger.html?wallet=#{boss.item.id})",
      "of [#{boss.login}](https://github.com/#{boss.login}),",
      "the balance is #{boss.wallet(&:balance)} (#{boss.wallet(&:txns).count}t);",
      "the exchange fee of #{amount * fee}",
      "was deposited to [#{rewards.item.id}](http://www.zold.io/ledger.html?wallet=#{rewards.item.id})",
      "of [#{rewards.login}](https://github.com/#{rewards.login}),",
      "the balance is #{rewards.wallet(&:balance)} (#{rewards.wallet(&:txns).count}t)"
    )
    if boss.wallet(&:txns).count > 1000
      ops(boss).migrate(settings.config['exchange']['keygap'])
      settings.telepost.spam(
        'The office wallet has been migrated to a new place',
        "[#{boss.item.id}](http://www.zold.io/ledger.html?wallet=#{boss.item.id}),",
        "the balance is #{boss.wallet(&:balance)}"
      )
    end
  end
  flash('/btc', "We took #{amount} from your wallet and sent you #{bitcoin} BTC")
end

get '/job' do
  uuid = params['id']
  raise UserError, "Job ID #{uuid} is not found" unless settings.jobs.exists?(uuid)
  content_type 'text/plain', charset: 'utf-8'
  settings.jobs.get(uuid)
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
    page_title: '/remotes'
  )
end

get '/rate' do
  unless settings.zache.exists?(:rate) && !settings.zache.expired?(:rate)
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
        root: settings.wallets.acq(Zold::Id::ROOT, &:balance) * -1,
        boss_wallet: boss.item.id
      }
      hash[:rate] = hash[:bank] / (hash[:root] - hash[:boss]).to_f
      hash[:deficit] = (hash[:root] - hash[:boss]).to_f * rate - hash[:bank]
      hash[:price] = settings.btc.price
      hash[:usd_rate] = hash[:price] * rate
      settings.zache.put(:rate, hash, lifetime: 10 * 60)
      settings.zache.remove_by { |k| k.to_s.start_with?('http', '/') }
      unless settings.ticks.exists?
        settings.ticks.add(
          'Fund' => (hash[:bank] * 100_000_000).to_i, # in satoshi
          'Emission' => hash[:root].to_i, # in zents
          'Office' => hash[:boss].to_i, # in zents
          'Rate' => (rate * 100_000_000).to_i, # satoshi per ZLD
          'Coverage' => (hash[:rate] * 100_000_000).to_i, # satoshi per ZLD
          'Deficit' => (hash[:deficit] * 100_000_000).to_i, # in satoshi
          'Price' => (hash[:price] * 100).to_i, # US cents per BTC
          'Value' => (hash[:usd_rate] * 100).to_i, # US cents per ZLD
          'Pledge' => (hash[:price] * hash[:rate] * 100).to_i # US cents per ZLD, covered
        )
      end
    end
  end
  flash('/', 'Still working on it, come back in a few seconds') unless settings.zache.exists?(:rate)
  haml :rate, layout: :layout, locals: merged(
    page_title: '/rate',
    formula: settings.zache.get(:rate),
    mtime: settings.zache.mtime(:rate)
  )
end

get '/rate.json' do
  content_type 'application/json'
  if settings.zache.exists?(:rate)
    hash = settings.zache.get(:rate)
    JSON.pretty_generate(
      valid: true,
      bank: hash[:bank],
      boss: hash[:boss].to_i,
      root: hash[:root].to_i,
      rate: hash[:rate].round(8),
      effective_rate: rate,
      deficit: hash[:deficit].round(2),
      price: hash[:price].round,
      usd_rate: hash[:usd_rate].round(4)
    )
  else
    JSON.pretty_generate(
      valid: false,
      effective_rate: rate,
      usd_rate: 1.0 # just for testing
    )
  end
end

get '/graph.svg' do
  content_type 'image/svg+xml'
  settings.zache.clean
  settings.zache.get(request.url, lifetime: 10 * 60) do
    Graph.new(settings.ticks).svg(params['keys'].split(' '), params['div'].to_i, params['digits'].to_i)
  end
end

get '/mobile/send' do
  phone = params[:phone]
  raise UserError, 'Mobile phone number is required' if phone.nil?
  raise UserError, "Invalid phone #{phone.inspect}, must be digits only as in E.164" unless /^[0-9]+$/.match?(phone)
  raise UserError, 'The phone shouldn\'t start with zeros' if /^0+/.match?(phone)
  phone = phone.to_i
  u = user(phone.to_s)
  u.create unless u.item.exists?
  job(u) do
    log(u).info("Just created a new wallet #{u.item.id}, going to push it...")
    ops(u).push
  end
  mcode = rand(1000..9999)
  u.item.mcode_set(mcode)
  cid = settings.smss.send(phone, "Your authorization code for wts.zold.io is: #{mcode}")
  if params[:noredirect]
    content_type 'text/plain'
    return cid.to_s
  end
  flash("/mobile_token?phone=#{phone}", "The SMS ##{cid} was sent with the auth code")
end

get '/mobile/token' do
  phone = params[:phone]
  raise UserError, 'Mobile phone number is required' if phone.nil?
  raise UserError, "Invalid phone #{phone.inspect}, must be digits only as in E.164" unless /^[0-9]+$/.match?(phone)
  raise UserError, 'The phone shouldn\'t start with zeros' if /^0+/.match?(phone)
  phone = phone.to_i
  mcode = params[:code]
  raise UserError, 'Mobile confirmation code is required' if mcode.nil?
  raise UserError, "Invalid code #{mcode.inspect}, must be four digits" unless /^[0-9]{4}$/.match?(mcode)
  u = user(phone.to_s)
  raise UserError, 'Mobile code mismatch' unless u.item.mcode == mcode.to_i
  token = "#{u.login}-#{u.item.token}"
  if params[:noredirect]
    content_type 'text/plain'
    return token
  end
  cookies[:wts] = token
  flash('/home', 'You have been logged in successfully')
end

get '/payables' do
  haml :payables, layout: :layout, locals: merged(
    page_title: 'Payables',
    payables: settings.payables
  )
end

get '/gl' do
  haml :gl, layout: :layout, locals: merged(
    page_title: 'General Ledger',
    gl: settings.gl,
    since: params[:since] ? Zold::Txn.parse_time(params[:since]) : nil
  )
end

get '/quick' do
  flash('/home', 'Please logout first') if @locals[:guser]
  haml :quick, layout: :layout, locals: merged(
    page_title: 'Zold: Quick Start',
    header_off: true
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

get '/js/*.js' do
  content_type 'application/javascript'
  IO.read(File.join('assets/js', params[:splat].first) + '.js')
end

not_found do
  status 404
  content_type 'text/html', charset: 'utf-8'
  haml :not_found, layout: :layout, locals: merged(
    page_title: 'Page not found'
  )
end

error do
  e = env['sinatra.error']
  if e.is_a?(UserError)
    settings.log.error("#{request.url}: #{e.message}")
    body(Backtrace.new(e).to_s)
    headers['X-Zold-Error'] = e.message[0..256]
    flash('/', e.message, error: true) unless params[:noredirect]
  end
  status 503
  Raven.capture_exception(e)
  haml :error, layout: :layout, locals: merged(
    page_title: 'Error',
    error: Backtrace.new(e).to_s
  )
end

private

def rate
  0.00026
end

def fee
  known? ? 0.02 : 0.08
end

def sell_limit
  Zold::Amount.new(zld: 32.0)
end

def title(suffix = '')
  raise UserError, 'title() cannot be used here' unless @locals[:guser]
  login = user.login
  (/^[0-9]/.match?(login) ? "+#{login}" : "@#{login}") + (suffix.empty? ? '' : '/' + suffix)
end

def title_md(u = user)
  if /^[0-9]/.match?(u.login)
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
  raise UserError, "You, #{login}, have to confirm your keygap first" unless u.confirmed?
  u
end

# This user is known as Zerocracy contributor.
def known?
  return false unless @locals[:guser]
  Zold::Http.new(uri: 'https://www.0crat.com/known/' + user.login).get.code == 200
end

def keygap
  gap = params[:keygap]
  raise UserError, 'Keygap is required' if gap.nil?
  begin
    confirmed_user.item.key(gap).to_s
  rescue StandardError => e
    raise UserError, "This doesn\'t seem to be a valid keygap: '#{'*' * gap.length}' (#{e.class.name})"
  end
  gap
end

def latch(login = @locals[:guser])
  File.join(settings.root, "latch/#{login}")
end

def network
  ENV['RACK_ENV'] == 'test' ? 'test' : 'zold'
end

def ops(u = user, log: log(u.login))
  Ops.new(
    u.item,
    u,
    settings.wallets,
    settings.remotes,
    settings.copies,
    log: log,
    network: network
  )
end

def job(u = user)
  uuid = SecureRandom.uuid
  settings.jobs.put(uuid, 'Running', lifetime: 60 * 60)
  lg = log(u.login)
  job = SafeJob.new(
    ZacheJob.new(
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
      uuid,
      settings.jobs
    ),
    log: lg
  )
  job = AsyncJob.new(job, settings.pool, latch(u.login)) unless ENV['RACK_ENV'] == 'test'
  job.call
  uuid
end

def pay_hosting_bonuses(boss)
  bonus = Zold::Amount.new(zld: 1.0)
  ops(boss).pull
  latest = boss.wallet(&:txns).reverse.find { |t| t.amount.negative? }
  return if !latest.nil? && latest.date > Time.now - 60 * 60
  if boss.wallet(&:balance) < bonus
    if !latest.nil? && latest.date > Time.now - 60 * 60
      settings.telepost.spam(
        'The hosting bonuses paying wallet',
        "[#{boss.item.id}](http://www.zold.io/ledger.html?wallet=#{boss.item.id})",
        "is almost empty, the balance is just #{boss.wallet(&:balance)};",
        "we can\'t pay #{bonus} of bonuses now;",
        'we should wait until the next BTC/ZLD',
        '[exchange](https://blog.zold.io/2018/12/09/btc-to-zld.html) happens.'
      )
    end
    return
  end
  require 'zold/commands/remote'
  cmd = Zold::Remote.new(remotes: settings.remotes, log: log(boss.login))
  cmd.run(%w[remote update --depth=5])
  winners = cmd.run(%w[remote elect --min-score=2 --max-winners=8 --ignore-masters])
  winners.each do |score|
    ops(boss).pay(
      settings.config['rewards']['keygap'],
      score.invoice,
      bonus / winners.count,
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
    return
  end
  settings.telepost.spam(
    'Hosting [bonus](https://blog.zold.io/2018/08/14/hosting-bonuses.html)',
    "of #{bonus} has been distributed among #{winners.count} wallets",
    '[visible](https://wts.zold.io/remotes) to us at the moment,',
    "among #{settings.remotes.all.count} [others](http://www.zold.io/health.html):",
    winners.map do |s|
      "[#{s.host}:#{s.port}](http://www.zold.io/ledger.html?wallet=#{s.invoice.split('@')[1]})/#{s.value}"
    end.join(', ') + ';',
    "the payer is #{title_md(boss)} with the wallet",
    "[#{boss.item.id}](http://www.zold.io/ledger.html?wallet=#{boss.item.id}),",
    "the remaining balance is #{boss.wallet(&:balance)} (#{boss.wallet(&:txns).count}t)"
  )
  return if boss.wallet(&:txns).count < 1000
  ops(boss).migrate(settings.config['rewards']['keygap'])
  settings.telepost.spam(
    'The wallet with hosting [bonuses](https://blog.zold.io/2018/08/14/hosting-bonuses.html)',
    'has been migrated to a new place',
    "[#{boss.item.id}](http://www.zold.io/ledger.html?wallet=#{boss.item.id}),",
    "the balance is #{boss.wallet(&:balance)}"
  )
end
