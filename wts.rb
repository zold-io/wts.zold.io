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
require 'yaml'
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
require 'telebot'
require 'rack/ssl'
require 'get_process_mem'
require 'total'
require 'zold'
require 'zold/hands'
require 'zold/log'
require 'zold/remotes'
require 'zold/amount'
require 'zold/json_page'
require 'zold/sync_wallets'
require 'zold/cached_wallets'
require_relative 'objects/wts'
require_relative 'objects/toggles'
require_relative 'objects/callbacks'
require_relative 'objects/tokens'
require_relative 'objects/addresses'
require_relative 'objects/jobs'
require_relative 'objects/payables'
require_relative 'objects/mcodes'
require_relative 'objects/smss'
require_relative 'objects/referrals'
require_relative 'objects/payouts'
require_relative 'objects/daemons'
require_relative 'objects/ticks'
require_relative 'objects/graph'
require_relative 'objects/item'
require_relative 'objects/user'
require_relative 'objects/btc'
require_relative 'objects/bank'
require_relative 'objects/paypal'
require_relative 'objects/hashes'
require_relative 'objects/user_error'
require_relative 'objects/ops'
require_relative 'objects/gl'
require_relative 'objects/pgsql'
require_relative 'objects/async_job'
require_relative 'objects/safe_job'
require_relative 'objects/update_job'
require_relative 'objects/tracked_job'
require_relative 'objects/versioned_job'
require_relative 'objects/file_log'
require_relative 'objects/tee_log'
require_relative 'objects/db_log'
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
      'rewards' => {
        'login' => '0crat',
        'keygap' => '?'
      },
      'exchange' => {
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
  set :gl, WTS::Gl.new(settings.pgsql, log: settings.log)
  set :payables, WTS::Payables.new(settings.pgsql, settings.remotes, log: settings.log)
  set :toggles, WTS::Toggles.new(settings.pgsql, log: settings.log)
  set :addresses, WTS::Addresses.new(settings.pgsql, log: settings.log)
  set :hashes, WTS::Hashes.new(settings.pgsql, log: settings.log)
  set :tokens, WTS::Tokens.new(settings.pgsql, log: settings.log)
  set :referrals, WTS::Referrals.new(settings.pgsql, log: settings.log)
  set :jobs, WTS::Jobs.new(settings.pgsql, log: settings.log)
  set :mcodes, WTS::Mcodes.new(settings.pgsql, log: settings.log)
  set :payouts, WTS::Payouts.new(settings.pgsql, log: settings.log)
  set :callbacks, WTS::Callbacks.new(settings.pgsql, log: settings.log)
  set :daemons, WTS::Daemons.new(settings.pgsql, log: settings.log)
  set :codec, GLogin::Codec.new(config['api_secret'])
  set :zache, Zache.new(dirty: true)
  set :ticks, WTS::Ticks.new(settings.pgsql, log: settings.log)
  set :pool, Concurrent::FixedThreadPool.new(16, max_queue: 64, fallback_policy: :abort)
  set :paypal, WTS::PayPal.new(
    {
      email: settings.config['paypal']['email'],
      login: settings.config['paypal']['login'],
      password: settings.config['paypal']['password'],
      signature: settings.config['paypal']['signature'],
      appid: settings.config['paypal']['appid']
    },
    log: settings.log
  )
  if settings.config['blockchain']['xpub'].empty?
    set :btc, WTS::Btc::Fake.new
  else
    set :btc, WTS::Btc.new(
      settings.config['blockchain']['xpub'],
      settings.config['blockchain']['key'],
      log: settings.log
    )
  end
  set :smss, WTS::Smss.new(
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
    settings.daemons.start('telepost') do
      settings.telepost.run
    end
  end
  settings.daemons.start('hosting-bonuses', 10 * 60) do
    login = settings.config['rewards']['login']
    boss = user(login)
    if boss.item.exists?
      job(boss) do |jid, log|
        pay_hosting_bonuses(boss, jid, log)
      end
    end
  end
  settings.daemons.start('scan-general-ledger') do
    settings.gl.scan(settings.remotes) do |t|
      settings.log.info("A new transaction added to the General Ledger \
for #{t[:amount].to_zld(6)} from #{t[:source]} to #{t[:target]} with details \"#{t[:details]}\" \
and dated of #{t[:date].utc.iso8601}")
      settings.callbacks.match(t[:target], t[:prefix], t[:details]) do |c, mid|
        settings.telepost.spam(
          "The callback no.#{c[:id]} owned by #{title_md(user(c[:login]))} just matched",
          "in [#{c[:wallet]}](http://www.zold.io/ledger.html?wallet=#{c[:wallet]})",
          "with prefix `#{c[:prefix]}` and details #{t[:details].inspect}, match ID is #{mid}"
        )
      end
    end
  end
  settings.daemons.start('callbacks', 5 * 60) do
    settings.callbacks.ping do |login, id, pfx, regexp|
      ops(user(login)).pull(id)
      settings.wallets.acq(id) do |wallet|
        wallet.txns.select do |t|
          t.prefix == pfx && regexp.match?(t.details)
        end
      end
    end
    settings.callbacks.delete_succeeded do |c|
      settings.telepost.spam(
        "The callback no.#{c[:id]} owned by #{title_md(user(c[:login]))} was deleted, since it was delivered;",
        "the wallet was [#{c[:wallet]}](http://www.zold.io/ledger.html?wallet=#{c[:wallet]})",
        "the prefix was `#{c[:prefix]}` and the regexp was `#{c[:regexp].inspect}`"
      )
    end
    settings.callbacks.delete_expired do |c|
      settings.telepost.spam(
        "The callback no.#{c[:id]} owned by #{title_md(user(c[:login]))} was deleted, since it was never matched;",
        "the wallet was [#{c[:wallet]}](http://www.zold.io/ledger.html?wallet=#{c[:wallet]})",
        "the prefix was `#{c[:prefix]}` and the regexp was `#{c[:regexp].inspect}`"
      )
    end
    settings.callbacks.delete_failed do |c|
      settings.telepost.spam(
        "The callback no.#{c[:id]} owned by #{title_md(user(c[:login]))} was deleted,",
        'since it was failed for over four hours;',
        "the wallet was [#{c[:wallet]}](http://www.zold.io/ledger.html?wallet=#{c[:wallet]})",
        "the prefix was `#{c[:prefix]}` and the regexp was `#{c[:regexp].inspect}`"
      )
    end
  end
  settings.daemons.start('payables', 10 * 60) do
    settings.payables.remove_old
    settings.payables.discover
    settings.payables.update
    settings.payables.remove_banned
  end
  settings.daemons.start('ticks', 10 * 60) do
    settings.ticks.add('Volume24' => settings.gl.volume.to_f) unless settings.ticks.exists?('Volume24')
    settings.ticks.add('Txns24' => settings.gl.count.to_f) unless settings.ticks.exists?('Txns24')
    boss = user(settings.config['rewards']['login'])
    job(boss) do
      settings.ticks.add('Nodes' => settings.remotes.all.count) unless settings.ticks.exists?('Nodes')
    end
  end
  settings.daemons.start('snapshot', 24 * 60 * 60) do
    coverage = settings.ticks.latest('Coverage') / 100_000_000
    distributed = Zold::Amount.new(
      zents: (settings.ticks.latest('Emission') - settings.ticks.latest('Office')).to_i
    )
    settings.telepost.spam(
      [
        "Today is #{Time.now.utc.strftime('%d-%b-%Y')} and we are doing great:\n",
        "  Wallets: [#{settings.payables.total}](https://wts.zold.io/payables)",
        "  Transactions: [#{settings.payables.txns}](https://wts.zold.io/payables)",
        "  Total emission: [#{settings.payables.balance}](https://wts.zold.io/payables)",
        "  Distributed: [#{distributed}](https://wts.zold.io/rate)",
        "  24-hours volume: [#{settings.gl.volume}](https://wts.zold.io/gl)",
        "  24-hours txns count: [#{settings.gl.count}](https://wts.zold.io/gl)",
        "  Nodes: [#{settings.remotes.all.count}](https://wts.zold.io/remotes)",
        "  Bitcoin price: $#{price.round}",
        "  Rate: [#{format('%.08f', rate)}](https://wts.zold.io/rate) ($#{(price * rate).round(2)})",
        "  Coverage: [#{format('%.08f', coverage)}](https://wts.zold.io/rate) \
/ [#{(100 * coverage / rate).round}%](http://papers.zold.io/fin-model.pdf)",
        "  BTC fund: [#{bank.balance.round(4)}](https://wts.zold.io/rate) ($#{(price * bank.balance).round})",
        "\nThanks for staying with us!"
      ].join("\n")
    )
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
    raise WTS::UserError, "101: The param #{k.inspect} can't be empty" if v.nil?
    raise WTS::UserError, "102: Invalid encoding of #{k.inspect} param" unless v.valid_encoding?
  end
end

after do
  headers['Access-Control-Allow-Origin'] = '*'
end

get '/github-callback' do
  c = GLogin::Cookie::Open.new(
    settings.glogin.user(params[:code]),
    settings.config['github']['encryption_secret'],
    context
  )
  cookies[:glogin] = c.to_s
  unless known?(c.login) || vip?(c.login)
    raise WTS::UserError, "103: @#{c.login} doesn't work in Zerocracy, can't login via GitHub, use mobile phone"
  end
  register_referral(c.login)
  flash('/', "You have been logged in as @#{c.login}")
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

get '/funded' do
  # Here we have to go to Coinbase and purchase BTC. This is necessary
  # in order to convert incoming USD immediately into Bitcoins, before
  # the rate changes and we lose some money.
  raise UserError, '104: Amount parameter is mandatory' unless params[:amount]
  amount = params[:amount].to_f
  raise UserError, '105: The amount can\'t be zero' if amount.zero?
  'OK, thanks'
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
  prohibit('create')
  job do |jid, log|
    log.info('Creating a new wallet by /create request...')
    user.create(settings.remotes)
    ops(log: log).push
    settings.telepost.spam(
      "The user #{title_md}",
      "created a new wallet [#{user.item.id}](http://www.zold.io/ledger.html?wallet=#{user.item.id})",
      "from #{anon_ip};",
      job_link(jid)
    )
    if user.item.tags.exists?('sign-up-bonus')
      settings.log.debug("Won't send sign-up bonus to #{user.login}, it's already there")
    elsif known?
      boss = user(settings.config['rewards']['login'])
      amount = Zold::Amount.new(zld: 0.256)
      job(boss) do |jid2, log2|
        if boss.wallet(&:balance) < amount
          settings.telepost.spam(
            "A sign-up bonus of #{amount} can't be sent",
            "to #{title_md} from #{anon_ip}",
            "to their wallet [#{user.item.id}](http://www.zold.io/ledger.html?wallet=#{user.item.id})",
            "from our wallet [#{boss.item.id}](http://www.zold.io/ledger.html?wallet=#{boss.item.id})",
            "of [#{boss.login}](https://github.com/#{boss.login})",
            "because there is not enough found, only #{boss.wallet(&:balance)} left;",
            job_link(jid2)
          )
        else
          ops(boss, log: log2).pull
          ops(boss, log: log2).pay(
            settings.config['rewards']['keygap'], user.item.id,
            amount, "WTS signup bonus to #{user.login}"
          )
          ops(boss, log: log2).push
          user.item.tags.attach('sign-up-bonus')
          settings.telepost.spam(
            "The sign-up bonus of #{amount} has been sent",
            "to #{title_md} from #{anon_ip},",
            "to their wallet [#{user.item.id}](http://www.zold.io/ledger.html?wallet=#{user.item.id})",
            "from our wallet [#{boss.item.id}](http://www.zold.io/ledger.html?wallet=#{boss.item.id})",
            "of [#{boss.login}](https://github.com/#{boss.login})",
            "with the remaining balance of #{boss.wallet(&:balance)} (#{boss.wallet(&:txns).count}t);",
            job_link(jid2)
          )
        end
      end
    elsif !user.mobile?
      settings.telepost.spam(
        "A sign-up bonus won't be sent to #{title_md} from #{anon_ip}",
        "with the wallet [#{user.item.id}](http://www.zold.io/ledger.html?wallet=#{user.item.id})",
        "because this user is not [known](https://www.0crat.com/known/#{user.login}) to Zerocracy;",
        job_link(jid)
      )
    end
  end
  flash('/', 'Your wallet is created and will be pushed soon')
end

get '/confirm' do
  raise WTS::UserError, '106: You have done this already, your keygap has been generated' if user.confirmed?
  haml :confirm, layout: :layout, locals: merged(
    page_title: title('keygap')
  )
end

get '/confirmed' do
  content_type 'text/plain'
  user.confirmed? ? 'yes' : 'no'
end

get '/do-confirm' do
  raise WTS::UserError, '107: You have done this already, your keygap has been generated' if user.confirmed?
  user.confirm(params[:keygap])
  flash('/', 'The account has been confirmed')
end

get '/keygap' do
  raise WTS::UserError, '108: We don\'t have it in the database anymore' if user.item.wiped?
  content_type 'text/plain'
  user.item.keygap
end

get '/pay' do
  prohibit('pay')
  haml :pay, layout: :layout, locals: merged(
    page_title: title('pay')
  )
end

post '/do-pay' do
  prohibit('pay')
  raise WTS::UserError, '109: Parameter "bnf" is not provided' if params[:bnf].nil?
  raise WTS::UserError, '110: Parameter "amount" is not provided' if params[:amount].nil?
  raise WTS::UserError, '111: Parameter "details" is not provided' if params[:details].nil?
  if /^[a-f0-9]{16}$/.match?(params[:bnf])
    bnf = Zold::Id.new(params[:bnf])
    raise WTS::UserError, '112: You can\'t pay yourself' if bnf == user.item.id
  elsif /^[a-zA-Z0-9]+@[a-f0-9]{16}$/.match?(params[:bnf])
    bnf = params[:bnf]
    raise WTS::UserError, '113: You can\'t pay yourself' if bnf.split('@')[1] == user.item.id.to_s
  elsif /^\\+[0-9]+$/.match?(params[:bnf])
    friend = user(params[:bnf][0..32].to_i.to_s)
    raise WTS::UserError, '114: The user with this mobile phone is not registered yet' unless friend.item.exists?
    bnf = friend.item.id
  else
    login = params[:bnf].strip.downcase.gsub(/^@/, '')
    raise WTS::UserError, "115: Invalid GitHub user name: #{params[:bnf].inspect}" unless login =~ /^[a-z0-9-]{3,32}$/
    raise WTS::UserError, '116: You can\'t pay yourself' if login == user.login
    friend = user(login)
    unless friend.item.exists?
      friend.create(settings.remotes)
      ops(friend).push
    end
    bnf = friend.item.id
  end
  amount = Zold::Amount.new(zld: params[:amount].to_f)
  if settings.toggles.get('ban:do-pay').split(',').include?(confirmed_user.login)
    settings.telepost.spam(
      "The user #{title_md} from #{anon_ip} is trying to send #{amount} out,",
      'while their account is banned via "ban:do-pay";',
      "the balance of the user is #{user.wallet(&:balance)}",
      "at the wallet [#{user.item.id}](http://www.zold.io/ledger.html?wallet=#{user.item.id})"
    )
    raise WTS::UserError, '117: Your account is not allowed to send any payments at the moment, sorry'
  end
  details = params[:details]
  raise WTS::UserError, "118: Invalid details \"#{details}\"" unless details =~ %r{^[a-zA-Z0-9\ @!?*_\-.:,'/]+$}
  headers['X-Zold-Job'] = job do |jid, log|
    log.info("Sending #{amount} to #{bnf}...")
    ops(log: log).pull
    raise WTS::UserError, "119: You don't have enough funds to send #{amount}" if user.wallet(&:balance) < amount
    txn = ops(log: log).pay(keygap, bnf, amount, details)
    settings.jobs.result(jid, 'txn', txn.id.to_s)
    settings.jobs.result(jid, 'tid', "#{user.item.id}:#{txn.id}")
    ops(log: log).push
    settings.telepost.spam(
      "Payment sent by #{title_md}",
      "from [#{user.item.id}](http://www.zold.io/ledger.html?wallet=#{user.item.id})",
      "with the balance of #{user.wallet(&:balance)}",
      "to [#{bnf}](http://www.zold.io/ledger.html?wallet=#{bnf})",
      "for **#{amount}** from #{anon_ip}:",
      "\"#{safe_md(details)}\";",
      job_link(jid)
    )
  end
  flash('/', "Payment has been sent to #{bnf} for #{amount}")
end

get '/pull' do
  headers['X-Zold-Job'] = job do |_jid, log|
    log.info("Pulling wallet #{user.item.id} via /pull...")
    if !user.wallet_exists? || params[:force]
      ops(log: log).remove
      ops(log: log).pull
    end
  end
  flash('/', "Your wallet #{user.item.id} will be pulled soon")
end

get '/restart' do
  prohibit('restart')
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
  prefix = inv.split('@')[0]
  content_type 'application/json'
  JSON.pretty_generate(prefix: prefix, invoice: inv)
end

get '/callbacks' do
  prohibit('api')
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
  prohibit('api')
  wallet = params[:wallet] || confirmed_user.item.id.to_s
  prefix = params[:prefix]
  raise WTS::UserError, '120: The parameter "prefix" is mandatory' if prefix.nil?
  regexp = params[:regexp] ? Regexp.new(params[:regexp]) : /^.*$/
  uri = URI(params[:uri])
  raise WTS::UserError, '121: The parameter "uri" is mandatory' if uri.nil?
  id = settings.callbacks.add(
    user.login, Zold::Id.new(wallet), prefix, regexp, uri,
    params[:token] || 'none'
  )
  settings.telepost.spam(
    "New callback no.#{id} created by #{title_md} from #{anon_ip}",
    "for the wallet [#{wallet}](http://www.zold.io/ledger.html?wallet=#{wallet}),",
    "prefix `#{prefix}`, and regular expression `#{safe_md(regexp.to_s)}`"
  )
  content_type 'text/plain'
  id.to_s
end

get '/migrate' do
  prohibit('migrate')
  haml :migrate, layout: :layout, locals: merged(
    page_title: title('migrate')
  )
end

get '/do-migrate' do
  prohibit('migrate')
  headers['X-Zold-Job'] = job do |jid, log|
    origin = user.item.id
    ops(log: log).migrate(keygap)
    settings.telepost.spam(
      "The wallet [#{origin}](http://www.zold.io/ledger.html?wallet=#{origin})",
      "with #{settings.wallets.acq(origin, &:txns).count} transactions",
      "and #{user.wallet(&:balance)}",
      "has been migrated to a new wallet [#{user.item.id}](http://www.zold.io/ledger.html?wallet=#{user.item.id})",
      "by #{title_md} from #{anon_ip}",
      job_link(jid)
    )
  end
  flash('/', 'You got a new wallet ID, your funds will be transferred soon...')
end

get '/btc-to-zld' do
  prohibit('btc')
  address = settings.addresses.acquire(confirmed_user.login) do
    address = settings.btc.create
    settings.telepost.spam(
      'New Bitcoin address acquired',
      "[#{address}](https://www.blockchain.com/btc/address/#{address})",
      "by request of #{title_md} from #{anon_ip};",
      "Blockchain.com gap is #{settings.btc.gap};",
      settings.btc.to_s
    )
    address
  end
  headers['X-Zold-BtcAddress'] = address
  haml :btc_to_zld, layout: :layout, locals: merged(
    page_title: title('buy'),
    gap: settings.zache.get(:gap, lifetime: 60) { settings.btc.gap },
    address: address
  )
end

# See https://www.blockchain.com/api/api_receive
get '/btc-hook' do
  settings.log.debug("Blockchain.com hook arrived: #{params}")
  raise WTS::UserError, '122: Confirmations is not provided' if params[:confirmations].nil?
  confirmations = params[:confirmations].to_i
  raise WTS::UserError, '123: Address is not provided' if params[:address].nil?
  address = params[:address]
  raise WTS::UserError, '124: Tx hash is not provided' if params[:transaction_hash].nil?
  hash = params[:transaction_hash]
  return '*ok*' if settings.hashes.seen?(hash)
  raise WTS::UserError, '125: Tx value is not provided' if params[:value].nil?
  satoshi = params[:value].to_i
  bitcoin = (satoshi.to_f / 100_000_000).round(8)
  zld = Zold::Amount.new(zld: bitcoin / rate)
  bnf = user(settings.addresses.find_user(address))
  raise WTS::UserError, "126: The user '#{bnf.login}' is not confirmed" unless bnf.confirmed?
  if confirmations.zero?
    settings.addresses.arrived(address, bnf.login)
    settings.telepost.spam(
      "Bitcoin transaction arrived for #{bitcoin} BTC",
      "to [#{address}](https://www.blockchain.com/btc/address/#{address})",
      "in [#{hash}](https://www.blockchain.com/btc/tx/#{hash})",
      "and was identified as belonging to #{title_md(bnf)},",
      "#{zld} will be deposited to the wallet",
      "[#{bnf.item.id}](http://www.zold.io/ledger.html?wallet=#{bnf.item.id})",
      "once we see enough confirmations, now it's #{confirmations} (may take up to an hour!)"
    )
  end
  unless settings.btc.exists?(hash, satoshi, address, confirmations)
    raise WTS::UserError, "127: Tx #{hash}/#{satoshi}/#{address} not found yet or is not yet confirmed enough"
  end
  boss = user(settings.config['exchange']['login'])
  job(boss) do |jid, log|
    if settings.hashes.seen?(hash)
      log.info("A duplicate notification from Blockchain about #{bitcoin} bitcoins \
arrival to #{address}, for #{bnf.login}; we ignore it.")
    else
      log.info("Accepting #{bitcoin} bitcoins from #{address}...")
      ops(boss, log: log).pull
      ops(boss, log: log).pay(
        settings.config['exchange']['keygap'],
        bnf.item.id,
        zld,
        "BTC exchange of #{bitcoin} at #{hash}, rate is #{rate}"
      )
      if settings.referrals.exists?(bnf.login)
        fee = settings.toggles.get('referral-fee', '0.04').to_f
        ops(boss, log: log).pay(
          settings.config['exchange']['keygap'],
          user(settings.referrals.get(bnf.login)).item.id,
          zld * fee, "#{(fee * 100).round(2)}% referral fee for BTC exchange"
        )
      end
      ops(boss, log: log).push
      settings.addresses.destroy(address, bnf.login)
      settings.hashes.add(hash, bnf.login, bnf.item.id)
      settings.telepost.spam(
        "In: #{bitcoin} BTC [exchanged](https://blog.zold.io/2018/12/09/btc-to-zld.html) to **#{zld}**",
        "by #{title_md(bnf)}",
        "in [#{hash}](https://www.blockchain.com/btc/tx/#{hash})",
        "(#{params[:confirmations]} confirmations)",
        "via [#{address}](https://www.blockchain.com/btc/address/#{address}),",
        "to the wallet [#{bnf.item.id}](http://www.zold.io/ledger.html?wallet=#{bnf.item.id})",
        "with the balance of #{bnf.wallet(&:balance)};",
        "the gap of Blockchain.com is #{settings.btc.gap};",
        "BTC price at the moment of exchange was [$#{price}](https://blockchain.info/ticker);",
        "the payer is #{title_md(boss)} with the wallet",
        "[#{boss.item.id}](http://www.zold.io/ledger.html?wallet=#{boss.item.id}),",
        "the remaining balance is #{boss.wallet(&:balance)} (#{boss.wallet(&:txns).count}t);",
        job_link(jid)
      )
    end
  end
  'Thanks!'
end

get '/queue' do
  raise WTS::UserError, '128: You are not allowed to see this' unless vip?
  content_type 'text/plain', charset: 'utf-8'
  settings.addresses.all.map do |a|
    "#{a[:login]} #{Zold::Age.new(a[:assigned])} #{a[:hash]} A=#{a[:arrived]}"
  end.join("\n")
end

get '/sql' do
  raise WTS::UserError, '129: You are not allowed to see this' unless vip?
  query = params[:query] || 'SELECT * FROM txn LIMIT 16'
  haml :sql, layout: :layout, locals: merged(
    page_title: title('SQL'),
    query: query,
    result: settings.pgsql.exec(query)
  )
end

get '/referrals' do
  haml :referrals, layout: :layout, locals: merged(
    page_title: title('referrals'),
    referrals: settings.referrals,
    fee: settings.toggles.get('referral-fee', '0.04').to_f
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

get '/zld-to-paypal' do
  prohibit('paypal')
  raise WTS::UserError, '130: You have to work in Zerocracy in order to cash out to PayPal' unless known?
  raise WTS::UserError, '131: You have to be identified in Zerocracy' unless kyc?
  haml :zld_to_paypal, layout: :layout, locals: merged(
    page_title: title('paypal'),
    rate: rate,
    price: price,
    fee: fee,
    user: confirmed_user
  )
end

post '/do-zld-to-paypal' do
  prohibit('paypal')
  raise WTS::UserError, '132: You have to work in Zerocracy in order to cash out to PayPal' unless known?
  raise WTS::UserError, '133: You have to be identified in Zerocracy' unless kyc?
  raise WTS::UserError, '134: Amount is not provided' if params[:amount].nil?
  raise WTS::UserError, '135: Email address is not provided' if params[:email].nil?
  raise WTS::UserError, '136: Keygap is not provided' if params[:keygap].nil?
  amount = Zold::Amount.new(zld: params[:amount].to_f)
  email = params[:email].strip
  raise WTS::UserError, "137: You don't have enough to send #{amount}" if confirmed_user.wallet(&:balance) < amount
  if settings.toggles.get('ban:do-sell').split(',').include?(user.login)
    settings.telepost.spam(
      "The user #{title_md} from #{anon_ip} is trying to send #{amount} to PayPal,",
      'while their account is banned via "ban:do-sell";',
      "the balance of the user is #{user.wallet(&:balance)}",
      "at the wallet [#{user.item.id}](http://www.zold.io/ledger.html?wallet=#{user.item.id})"
    )
    raise WTS::UserError, '138: Your account is not allowed to sell any ZLD at the moment, email us'
  end
  limits = settings.toggles.get('limits', '64/128/256')
  unless settings.payouts.allowed?(user.login, amount, limits) || vip?
    consumed = settings.payouts.consumed(user.login)
    settings.telepost.spam(
      "The user #{title_md} from #{anon_ip} with #{amount} payment to PayPal just attempted to go",
      "over their account limits: \"#{consumed}\", while allowed thresholds are \"#{limits}\";",
      "the balance of the user is #{user.wallet(&:balance)}",
      "at the wallet [#{user.item.id}](http://www.zold.io/ledger.html?wallet=#{user.item.id})"
    )
    raise WTS::UserError, "139: With #{amount} you are going over your limits, #{consumed} were sold already, \
while we allow one user to sell up to #{limits} (daily/weekly/monthly)"
  end
  limits = settings.toggles.get('system-limits', '512/2048/8196')
  unless settings.payouts.safe?(amount, limits) || vip?
    consumed = settings.payouts.system_consumed
    settings.telepost.spam(
      "The user #{title_md} from #{anon_ip} with #{amount} payment to PayPal just attempted to go",
      "over our limits: \"#{consumed}\", while allowed thresholds are \"#{limits}\";",
      "the balance of the user is #{user.wallet(&:balance)}",
      "at the wallet [#{user.item.id}](http://www.zold.io/ledger.html?wallet=#{user.item.id})"
    )
    raise WTS::UserError, "140: With #{amount} you are going over our limits, #{consumed} were sold by ALL \
users of WTS, while our limits are #{limits} (daily/weekly/monthly), sorry about this :("
  end
  bitcoin = (amount.to_zld(8).to_f * rate).round(8)
  usd = (bitcoin * price).round(2)
  boss = user(settings.config['exchange']['login'])
  rewards = user(settings.config['rewards']['login'])
  job do |jid, log|
    log.info("Sending $#{usd} via PayPal to #{email}...")
    f = fee
    ops(log: log).pull
    ops(rewards, log: log).pull
    ops(boss, log: log).pull
    txn = ops(log: log).pay(
      keygap,
      boss.item.id,
      amount * (1.0 - f),
      "ZLD exchange to #{usd} PayPal, rate is #{rate}, fee is #{f}"
    )
    ops(log: log).pay(
      keygap,
      rewards.item.id,
      amount * f,
      "Fee for exchange of #{usd} PayPal, rate is #{rate}, fee is #{f}"
    )
    ops(log: log).push
    settings.paypal.send(
      email,
      (usd * (1.0 - f)).round(2),
      "Zerocracy development, TID #{user.item.id}:#{txn.id}"
    )
    settings.payouts.add(
      user.login, user.item.id, amount,
      "$#{usd} sent to #{email}, the price was $#{price.round}/BTC, the fee was #{(f * 100).round(2)}%"
    )
    settings.telepost.spam(
      "Out: **#{amount}** [exchanged](https://blog.zold.io/2018/12/09/btc-to-zld.html) to $#{usd} PayPal",
      "by #{title_md} from #{anon_ip}",
      "from the wallet [#{user.item.id}](http://www.zold.io/ledger.html?wallet=#{user.item.id})",
      "with the remaining balance of #{user.wallet(&:balance)};",
      "BTC price at the time of exchange was [$#{price.round}](https://blockchain.info/ticker);",
      "zolds were deposited to [#{boss.item.id}](http://www.zold.io/ledger.html?wallet=#{boss.item.id})",
      "of [#{boss.login}](https://github.com/#{boss.login}),",
      "the balance is #{boss.wallet(&:balance)} (#{boss.wallet(&:txns).count}t);",
      "the exchange fee of #{amount * f}",
      "was deposited to [#{rewards.item.id}](http://www.zold.io/ledger.html?wallet=#{rewards.item.id})",
      "of [#{rewards.login}](https://github.com/#{rewards.login}),",
      "the balance is #{rewards.wallet(&:balance)} (#{rewards.wallet(&:txns).count}t);",
      job_link(jid)
    )
  end
  flash('/zld-to-paypal', "We took #{amount} from your wallet and sent you $#{usd} PayPal, more details in the log")
end

get '/zld-to-btc' do
  prohibit('btc')
  haml :zld_to_btc, layout: :layout, locals: merged(
    page_title: title('sell'),
    user: confirmed_user,
    rate: rate,
    fee: fee,
    price: price
  )
end

post '/do-zld-to-btc' do
  prohibit('sell')
  raise WTS::UserError, '141: Amount is not provided' if params[:amount].nil?
  raise WTS::UserError, '142: Bitcoin address is not provided' if params[:btc].nil?
  raise WTS::UserError, '143: Keygap is not provided' if params[:keygap].nil?
  amount = Zold::Amount.new(zld: params[:amount].to_f)
  address = params[:btc].strip
  raise WTS::UserError, "144: Bitcoin address is not valid: #{address.inspect}" unless address =~ /^[a-zA-Z0-9]+$/
  raise WTS::UserError, '145: Bitcoin address must start with 1, 3 or bc1' unless address =~ /^(1|3|bc1)/
  raise WTS::UserError, "146: You don't have enough to send #{amount}" if confirmed_user.wallet(&:balance) < amount
  if settings.toggles.get('ban:do-sell').split(',').include?(user.login)
    settings.telepost.spam(
      "The user #{title_md} from #{anon_ip} is trying to sell #{amount},",
      'while their account is banned via "ban:do-sell";',
      "the balance of the user is #{user.wallet(&:balance)}",
      "at the wallet [#{user.item.id}](http://www.zold.io/ledger.html?wallet=#{user.item.id})"
    )
    raise WTS::UserError, '147: Your account is not allowed to sell any ZLD at the moment, email us'
  end
  limits = settings.toggles.get('limits', '64/128/256')
  unless settings.payouts.allowed?(user.login, amount, limits) || vip?
    consumed = settings.payouts.consumed(user.login)
    settings.telepost.spam(
      "The user #{title_md} from #{anon_ip} with #{amount} payment just attempted to go",
      "over their account limits: \"#{consumed}\", while allowed thresholds are \"#{limits}\";",
      "the balance of the user is #{user.wallet(&:balance)}",
      "at the wallet [#{user.item.id}](http://www.zold.io/ledger.html?wallet=#{user.item.id})"
    )
    raise WTS::UserError, "148: With #{amount} you are going over your limits, #{consumed} were sold already, \
while we allow one user to sell up to #{limits} (daily/weekly/monthly)"
  end
  limits = settings.toggles.get('system-limits', '512/2048/8196')
  unless settings.payouts.safe?(amount, limits) || vip?
    consumed = settings.payouts.system_consumed
    settings.telepost.spam(
      "The user #{title_md} from #{anon_ip} with #{amount} payment just attempted to go",
      "over our limits: \"#{consumed}\", while allowed thresholds are \"#{limits}\";",
      "the balance of the user is #{user.wallet(&:balance)}",
      "at the wallet [#{user.item.id}](http://www.zold.io/ledger.html?wallet=#{user.item.id})"
    )
    raise WTS::UserError, "149: With #{amount} you are going over our limits, #{consumed} were sold by ALL \
users of WTS, while our limits are #{limits} (daily/weekly/monthly), sorry about this :("
  end
  bitcoin = (amount.to_zld(8).to_f * rate).round(8)
  usd = bitcoin * price
  boss = user(settings.config['exchange']['login'])
  rewards = user(settings.config['rewards']['login'])
  job do |jid, log|
    log.info("Sending #{bitcoin} bitcoins to #{address}...")
    f = fee
    ops(log: log).pull
    ops(rewards, log: log).pull
    ops(boss, log: log).pull
    ops(log: log).pay(
      keygap,
      boss.item.id,
      amount * (1.0 - f),
      "ZLD exchange to #{bitcoin} BTC at #{address}, rate is #{rate}, fee is #{f}"
    )
    ops(log: log).pay(
      keygap,
      rewards.item.id,
      amount * f,
      "Fee for exchange of #{bitcoin} BTC at #{address}, rate is #{rate}, fee is #{f}"
    )
    ops(log: log).push
    bank(log: log).send(
      address,
      (usd * (1.0 - f)).round(2),
      "Exchange of #{amount.to_zld(8)} by #{title} to #{user.item.id}, rate is #{rate}, fee is #{f}"
    )
    settings.payouts.add(
      user.login, user.item.id, amount,
      "#{bitcoin} BTC sent to #{address}, the price was $#{price.round}/BTC, the fee was #{(f * 100).round(2)}%"
    )
    settings.telepost.spam(
      "Out: #{amount} [exchanged](https://blog.zold.io/2018/12/09/btc-to-zld.html) to #{bitcoin} BTC",
      "by #{title_md} from #{anon_ip}",
      "from the wallet [#{user.item.id}](http://www.zold.io/ledger.html?wallet=#{user.item.id})",
      "with the remaining balance of #{user.wallet(&:balance)}",
      "to bitcoin address [#{address}](https://www.blockchain.com/btc/address/#{address});",
      "BTC price at the time of exchange was [$#{price.round}](https://blockchain.info/ticker);",
      "our bitcoin wallet still has #{bank.balance.round(3)} BTC",
      "(worth about $#{(bank.balance * price).round});",
      "zolds were deposited to [#{boss.item.id}](http://www.zold.io/ledger.html?wallet=#{boss.item.id})",
      "of [#{boss.login}](https://github.com/#{boss.login}),",
      "the balance is #{boss.wallet(&:balance)} (#{boss.wallet(&:txns).count}t);",
      "the exchange fee of #{amount * f}",
      "was deposited to [#{rewards.item.id}](http://www.zold.io/ledger.html?wallet=#{rewards.item.id})",
      "of [#{rewards.login}](https://github.com/#{rewards.login}),",
      "the balance is #{rewards.wallet(&:balance)} (#{rewards.wallet(&:txns).count}t);",
      job_link(jid)
    )
    if boss.wallet(&:txns).count > 1000
      ops(boss, log: log).migrate(settings.config['exchange']['keygap'])
      settings.telepost.spam(
        'The office wallet has been migrated to a new place',
        "[#{boss.item.id}](http://www.zold.io/ledger.html?wallet=#{boss.item.id}),",
        "the balance is #{boss.wallet(&:balance)};",
        job_link(jid)
      )
    end
  end
  flash('/zld-to-btc', "We took #{amount} from your wallet and sent you #{bitcoin} BTC, more details in the log")
end

get '/job' do
  prohibit('api')
  id = params['id']
  raise WTS::UserError, "150: Job in 'id' query parameter is mandatory" if id.nil? || id.empty?
  raise WTS::UserError, "151: Job ID #{id} is not found" unless settings.jobs.exists?(id)
  content_type 'text/plain', charset: 'utf-8'
  settings.jobs.read(id)
end

get '/job.json' do
  prohibit('api')
  id = params['id']
  raise WTS::UserError, "152: Job in 'id' query parameter is mandatory" if id.nil? || id.empty?
  raise WTS::UserError, "153: Job ID #{id} is not found" unless settings.jobs.exists?(id)
  content_type 'application/json'
  JSON.pretty_generate(
    {
      id: id,
      status: settings.jobs.status(id),
      output_length: settings.jobs.output(id).length
    }.merge(settings.jobs.results(id))
  )
end

get '/output' do
  prohibit('api')
  id = params['id']
  raise WTS::UserError, "154: Job in 'id' query parameter is mandatory" if id.nil? || id.empty?
  raise WTS::UserError, "155: Job ID #{id} is not found" unless settings.jobs.exists?(id)
  content_type 'text/plain', charset: 'utf-8'
  headers['X-Zold-JobStatus'] = settings.jobs.status(id)
  settings.jobs.output(id)
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

get '/rate' do
  unless settings.zache.exists?(:rate) && !settings.zache.expired?(:rate)
    boss = user(settings.config['exchange']['login'])
    job(boss) do |_jid, log|
      ops(boss, log: log).pull
      require 'zold/commands/pull'
      Zold::Pull.new(
        wallets: settings.wallets, remotes: settings.remotes, copies: settings.copies, log: settings.log
      ).run(['pull', Zold::Id::ROOT.to_s, "--network=#{network}"])
      hash = {
        bank: bank(log: log).balance,
        boss: settings.wallets.acq(boss.item.id, &:balance),
        root: settings.wallets.acq(Zold::Id::ROOT, &:balance) * -1,
        boss_wallet: boss.item.id
      }
      hash[:rate] = hash[:bank] / (hash[:root] - hash[:boss]).to_f
      hash[:deficit] = (hash[:root] - hash[:boss]).to_f * rate - hash[:bank]
      hash[:price] = price
      hash[:usd_rate] = hash[:price] * rate
      settings.zache.put(:rate, hash, lifetime: 10 * 60)
      settings.zache.remove_by { |k| k.to_s.start_with?('http', '/') }
      unless settings.ticks.exists?('Fund')
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
  raise WTS::UserError, "156: Param 'keys' is mandatory" unless params[:keys]
  raise WTS::UserError, "157: Param 'div' is mandatory" unless params[:div]
  raise WTS::UserError, "158: Param 'digits' is mandatory" unless params[:digits]
  content_type 'image/svg+xml'
  settings.zache.clean
  settings.zache.get(request.url, lifetime: 10 * 60) do
    WTS::Graph.new(settings.ticks).svg(
      params[:keys].split(' '),
      params[:div].to_i,
      params[:digits].to_i,
      title: params[:title] || ''
    )
  end
end

get '/mobile/send' do
  prohibit('api')
  phone = params[:phone]
  raise WTS::UserError, '159: Mobile phone number is required' if phone.nil?
  raise WTS::UserError, '160: Phone number can\'t be empty, format it according to E.164' if phone.empty?
  unless /^[0-9]+$/.match?(phone)
    raise WTS::UserError, "161: Invalid phone #{phone.inspect}, digits only allowed (E.164)"
  end
  raise WTS::UserError, '161: The phone shouldn\'t start with zeros' if /^0+/.match?(phone)
  raise WTS::UserError, "162: The phone number #{phone.inspect} is too short" if phone.length < 6
  raise WTS::UserError, "163: The phone number #{phone.inspect} is too long" if phone.length > 14
  phone = phone.to_i
  mcode = rand(1000..9999)
  if settings.mcodes.exists?(phone)
    mcode = settings.mcodes.get(phone)
  else
    settings.mcodes.set(phone, mcode)
  end
  cid = settings.smss.send(phone, "Your authorization code for wts.zold.io is: #{mcode}")
  if params[:noredirect]
    content_type 'text/plain'
    return cid.to_s
  end
  flash("/mobile_token?phone=#{phone}", "The SMS ##{cid} was sent with the auth code")
end

get '/mobile/token' do
  prohibit('api')
  phone = params[:phone]
  raise WTS::UserError, '164: Mobile phone number is required' if phone.nil?
  raise WTS::UserError, '165: Phone number can\'t be empty, format it according to E.164' if phone.empty?
  unless /^[0-9]+$/.match?(phone)
    raise WTS::UserError, "166: Invalid phone #{phone.inspect}, digits only allowed (E.164)"
  end
  phone = phone.to_i
  mcode = params[:code].strip
  raise WTS::UserError, '167: Mobile confirmation code can\'t be empty' if mcode.empty?
  raise WTS::UserError, "168: Invalid code #{mcode.inspect}, must be four digits" unless /^[0-9]{4}$/.match?(mcode)
  raise WTS::UserError, '169: Mobile code mismatch' unless settings.mcodes.get(phone) == mcode.to_i
  settings.mcodes.remove(phone)
  u = user(phone.to_s)
  u.create(settings.remotes) unless u.item.exists?
  job(u) do |_jid, log|
    log.info("Just created a new wallet #{u.item.id}, going to push it...")
    ops(u, log: log).push
  end
  token = "#{u.login}-#{settings.tokens.get(u.login)}"
  if params[:noredirect]
    content_type 'text/plain'
    return token
  end
  cookies[:wts] = token
  register_referral(u.login)
  flash('/home', 'You have been logged in successfully')
end

get '/toggles' do
  raise WTS::UserError, '170: You are not allowed to see this' unless vip?
  haml :toggles, layout: :layout, locals: merged(
    page_title: 'Toggles',
    toggles: settings.toggles
  )
end

post '/set-toggle' do
  raise WTS::UserError, '171: You are not allowed to see this' unless vip?
  key = params[:key].strip
  value = params[:value].strip
  settings.toggles.set(key, value)
  flash('/toggles', "The feature toggle #{key.inspect} re/set")
end

get '/payables' do
  haml :payables, layout: :layout, locals: merged(
    page_title: 'Payables',
    rate: rate,
    price: price,
    payables: settings.payables
  )
end

get '/gl' do
  haml :gl, layout: :layout, locals: merged(
    page_title: 'General Ledger',
    gl: settings.gl,
    query: (params[:query] || '').strip,
    since: params[:since] ? Zold::Txn.parse_time(params[:since]) : nil
  )
end

get '/quick' do
  prohibit('quick')
  flash('/home', 'Please logout first') if @locals[:guser]
  page = params[:haml] || 'default'
  raise WTS::UserError, '172: HAML page name is not valid' unless /^[a-zA-Z0-9]{,64}$/.match?(page)
  http = Zold::Http.new(uri: "https://raw.githubusercontent.com/zold-io/quick/master/#{page}.haml").get
  html = Haml::Engine.new(
    http.status == 200 ? http.body : IO.read(File.join(__dir__, 'views/quick_default.haml'))
  ).render(self)
  haml :quick, layout: :layout, locals: merged(
    page_title: 'Zold: Quick Start',
    header_off: true,
    html: html
  )
end

get '/terms' do
  haml :terms, layout: :layout, locals: merged(
    page_title: 'Terms of Use'
  )
end

get '/robots.txt' do
  content_type 'text/plain'
  "User-agent: *\nDisallow: /"
end

get '/version' do
  content_type 'text/plain'
  WTS::VERSION
end

get '/context' do
  content_type 'text/plain'
  context
end

get '/css/*.css' do
  name = params[:splat].first
  file = File.join('assets/sass', name) + '.sass'
  error(404, "File not found: #{file}") unless File.exist?(file)
  content_type 'text/css', charset: 'utf-8'
  sass name.to_sym, views: "#{settings.root}/assets/sass"
end

get '/js/*.js' do
  file = File.join('assets/js', params[:splat].first) + '.js'
  error(404, "File not found: #{file}") unless File.exist?(file)
  content_type 'application/javascript'
  IO.read(file)
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
  if e.is_a?(WTS::UserError)
    settings.log.error("#{request.url}: #{e.message}")
    body(Backtrace.new(e).to_s)
    headers['X-Zold-Error'] = e.message[0..256]
    if params[:noredirect]
      content_type 'text/plain', charset: 'utf-8'
      return Backtrace.new(e).to_s
    end
    flash('/', e.message, error: true)
  end
  status 503
  Raven.capture_exception(e, extra: { 'request_url' => request.url })
  if params[:noredirect]
    Backtrace.new(e).to_s
  else
    haml :error, layout: :layout, locals: merged(
      page_title: 'Error',
      error: Backtrace.new(e).to_s
    )
  end
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
  raise WTS::UserError, '173: You have to login first' unless login
  WTS::User.new(
    login, WTS::Item.new(login, settings.pgsql, log: user_log(login)),
    settings.wallets, log: user_log(login)
  )
end

def confirmed_user(login = @locals[:guser])
  u = user(login)
  raise WTS::UserError, "174: You, #{login}, have to confirm your keygap first" unless u.confirmed?
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
  raise WTS::UserError, '175: Keygap is required' if gap.nil?
  begin
    confirmed_user.item.key(gap).to_s
  rescue StandardError => e
    raise WTS::UserError, "176: This doesn\'t seem to be a valid keygap: '#{'*' * gap.length}' (#{e.class.name})"
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

def job(u = user)
  jid = settings.jobs.start(u.login)
  log = WTS::TeeLog.new(user_log(u.login), WTS::DbLog.new(settings.pgsql, jid))
  job = WTS::SafeJob.new(
    WTS::TrackedJob.new(
      WTS::VersionedJob.new(
        WTS::UpdateJob.new(
          proc { yield(jid, log) },
          settings.remotes,
          log: log,
          network: network
        ),
        log: log
      ),
      settings.jobs
    ),
    log: log
  )
  job = WTS::AsyncJob.new(job, settings.pool, latch(u.login)) unless ENV['RACK_ENV'] == 'test'
  job.call(jid)
  jid
end

def pay_hosting_bonuses(boss, jid, log)
  prohibit('bonuses')
  bonus = Zold::Amount.new(zld: 1.0)
  ops(boss, log: log).pull
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
        '[exchange](https://blog.zold.io/2018/12/09/btc-to-zld.html) happens;',
        job_link(jid)
      )
    end
    return
  end
  require 'zold/commands/remote'
  cmd = Zold::Remote.new(remotes: settings.remotes, log: log)
  cmd.run(%w[remote update --depth=5])
  cmd.run(%w[remote show])
  winners = cmd.run(%w[remote elect --min-score=2 --max-winners=8 --ignore-masters])
  winners.each do |score|
    ops(boss, log: log).pull
    ops(boss, log: log).pay(
      settings.config['rewards']['keygap'],
      score.invoice,
      bonus / winners.count,
      "Hosting bonus for #{score.host} #{score.port} #{score.value}"
    )
    ops(boss, log: log).push
  end
  if winners.empty?
    settings.telepost.spam(
      'Attention, no hosting [bonuses](https://blog.zold.io/2018/08/14/hosting-bonuses.html)',
      'were paid because no nodes were found,',
      "which would deserve that, among [#{settings.remotes.all.count} visible](https://wts.zold.io/remotes);",
      'something is wrong with the network,',
      'check this [health](http://www.zold.io/health.html) page;',
      job_link(jid)
    )
    return
  end
  settings.telepost.spam(
    'Hosting [bonus](https://blog.zold.io/2018/08/14/hosting-bonuses.html)',
    "of **#{bonus}** has been distributed among #{winners.count} wallets",
    '[visible](https://wts.zold.io/remotes) to us at the moment,',
    "among #{settings.remotes.all.count} [others](http://www.zold.io/health.html):",
    winners.map do |s|
      "[#{s.host}:#{s.port}](http://www.zold.io/ledger.html?wallet=#{s.invoice.split('@')[1]})/#{s.value}"
    end.join(', ') + ';',
    "the payer is #{title_md(boss)} with the wallet",
    "[#{boss.item.id}](http://www.zold.io/ledger.html?wallet=#{boss.item.id}),",
    "the remaining balance is #{boss.wallet(&:balance)} (#{boss.wallet(&:txns).count}t);",
    job_link(jid)
  )
  return if boss.wallet(&:txns).count < 1000
  before = boss.item.id
  ops(boss, log: log).migrate(settings.config['rewards']['keygap'])
  settings.telepost.spam(
    'The wallet with hosting [bonuses](https://blog.zold.io/2018/08/14/hosting-bonuses.html)',
    "has been migrated from [#{before}](http://www.zold.io/ledger.html?wallet=#{before})",
    "to a new place [#{boss.item.id}](http://www.zold.io/ledger.html?wallet=#{boss.item.id}),",
    "the balance is #{boss.wallet(&:balance)};",
    job_link(jid)
  )
end

def prohibit(feature)
  return unless settings.toggles.get("stop:#{feature}", 'no') == 'yes'
  raise WTS::UserError, "177: This feature \"#{feature}\" is temporarily disabled, sorry"
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

def price
  settings.zache.get(:price, lifetime: 5 * 60) { settings.btc.price }
end

def bank(log: settings.log)
  if settings.config['coinbase']['key'].empty?
    WTS::Bank::Fake.new
  else
    WTS::Bank.new(
      settings.config['coinbase']['key'],
      settings.config['coinbase']['secret'],
      settings.config['coinbase']['account'],
      log: log
    )
  end
end
