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
require 'sinatra'
require 'sinatra/cookies'
require 'sass'
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
  set :wallets, Zold::Wallets.new(File.join(settings.root, '.zold-wts/wallets'))
  set :remotes, Zold::Remotes.new(file: File.join(settings.root, '.zold-wts/remotes'), network: 'zold')
  set :copies, File.join(settings.root, '.zold-wts/copies')
  set :codec, GLogin::Codec.new(config['api_secret'])
  set :pool, Concurrent::FixedThreadPool.new(16, max_queue: 64, fallback_policy: :abort)
  set :log, Zold::Log::Regular.new
  Thread.new do
    loop do
      sleep 60 * 60
      begin
        pay_hosting_bonuses
      rescue StandardError => e
        settings.log.error("#{e.class.name}: #{e.message}\n\t#{e.backtrace.join("\n\t")}")
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
  cookies[:glogin] = params[:glogin] if params[:glogin]
  if cookies[:glogin]
    begin
      @locals[:guser] = GLogin::Cookie::Closed.new(
        cookies[:glogin],
        settings.config['github']['encryption_secret'],
        context
      ).to_user
    rescue OpenSSL::Cipher::CipherError => _
      @locals.delete(:user)
    end
  end
  header = request.env['HTTP_X_ZOLD_WTS']
  if header
    begin
      login, keygap = settings.codec.decrypt(header).split(' ')
      @locals[:guser] = { login: login }
      @locals[:keygap] = keygap
      settings.log.info("HTTP authentication header of @#{login} detected from #{request.ip}")
    rescue OpenSSL::Cipher::CipherError => _
      error 400
    end
  end
  if @locals[:guser]
    @locals[:user] = user(@locals[:guser][:login])
    @locals[:ops] = ops(@locals[:user])
  end
end

get '/github-callback' do
  cookies[:glogin] = GLogin::Cookie::Open.new(
    settings.glogin.user(params[:code]),
    settings.config['github']['encryption_secret'],
    context
  ).to_s
  redirect to('/')
end

get '/logout' do
  cookies.delete(:glogin)
  redirect to('/')
end

get '/' do
  redirect '/home' if @locals[:user]
  haml :index, layout: :layout, locals: merged(
    title: 'wts'
  )
end

get '/home' do
  redirect '/' unless @locals[:user]
  redirect '/create' unless @locals[:user].item.exists?
  redirect '/confirm' unless @locals[:user].confirmed?
  haml :home, layout: :layout, locals: merged(
    title: '@' + @locals[:guser][:login],
    start: params[:start] ? Time.parse(params[:start]) : nil
  )
end

get '/fund' do
  redirect '/' unless @locals[:user]
  redirect '/confirm' unless @locals[:user].confirmed?
  haml :fund, layout: :layout, locals: merged(
    title: '@' + @locals[:guser][:login] + '/fund'
  )
end

post '/do-fund' do
  redirect '/' unless @locals[:user]
  redirect '/confirm' unless @locals[:user].confirmed?
  amount = params[:amount].to_i
  redirect [
    'https://indacoin.com/gw/payment_form?',
    [
      'partner=zold',
      'cur_from=EUR',
      'cur_to=ETH',
      "amount=#{(amount / 100).round(2)}",
      'address=0xFb96dc76d73bDBc2193919EC16bB3a6464f85BaA',
      "user_id=#{@locals[:guser][:login]}"
    ].join('&')
  ].join
end

get '/indacoin' do
  puts params
  p params
  ops(user(settings.config['rewards']['login'])).pay(
    settings.config['rewards']['keygap'], user(params[:user]).item.id,
    Zold::Amount.new(zld: params[:amount].to_i), 'Purchase via Indacoin'
  )
end

get '/create' do
  redirect '/' unless @locals[:user]
  @locals[:user].create
  pay_bonus
  @locals[:ops].push
  log.info("Wallet #{@locals[:user].item.id} created and pushed by @#{@locals[:guser][:login]}\n")
  redirect '/'
end

get '/confirm' do
  redirect '/' unless @locals[:user]
  redirect '/home' if @locals[:user].confirmed?
  haml :confirm, layout: :layout, locals: merged(
    title: '@' + @locals[:guser][:login] + '/keygap'
  )
end

get '/keygap' do
  redirect '/' unless @locals[:user]
  redirect '/' if @locals[:user].confirmed?
  content_type 'text/plain'
  @locals[:user].item.keygap
end

get '/do-confirm' do
  redirect '/' unless @locals[:user]
  @locals[:user].confirm(params[:keygap])
  log.info("Account confirmed for @#{@locals[:guser][:login]}\n")
  redirect '/'
end

get '/pay' do
  redirect '/' unless @locals[:user]
  redirect '/confirm' unless @locals[:user].confirmed?
  haml :pay, layout: :layout, locals: merged(
    title: '@' + @locals[:guser][:login] + '/pay'
  )
end

post '/do-pay' do
  redirect '/' unless @locals[:user]
  redirect '/confirm' unless @locals[:user].confirmed?
  if params[:bnf] =~ /[a-f0-9]{16}/
    bnf = Zold::Id.new(params[:bnf])
  else
    login = params[:bnf].strip.downcase.gsub(/^@/, '')
    raise "Invalid GitHub user name: '#{params[:bnf]}'" unless login =~ /^[a-z0-9]{3,32}$/
    friend = user(login)
    unless friend.item.exists?
      friend.create
      ops(friend).push
    end
    bnf = friend.item.id
  end
  amount = Zold::Amount.new(zld: params[:amount].to_f)
  details = params[:details]
  params[:keygap] = params[:pass] if params[:pass]
  keygap = @locals[:keygap].nil? ? params[:keygap] : @locals[:keygap]
  @locals[:ops].pay(keygap, bnf, amount, details)
  log.info("Payment made by @#{@locals[:guser][:login]} to #{bnf} for #{amount}\n \n")
  redirect '/'
end

get '/pull' do
  redirect '/' unless @locals[:user]
  redirect '/confirm' unless @locals[:user].confirmed?
  @locals[:ops].pull
  log.info("Wallet #{@locals[:user].item.id} pulled by @#{@locals[:guser][:login]}\n \n")
  redirect '/'
end

get '/push' do
  redirect '/' unless @locals[:user]
  redirect '/confirm' unless @locals[:user].confirmed?
  @locals[:ops].push
  log.info("Wallet #{@locals[:user].item.id} pushed by @#{@locals[:guser][:login]}\n \n")
  redirect '/'
end

get '/key' do
  redirect '/' unless @locals[:user]
  redirect '/confirm' unless @locals[:user].confirmed?
  haml :key, layout: :layout, locals: merged(
    title: '@' + @locals[:guser][:login] + '/key'
  )
end

get '/keygap' do
  redirect '/' unless @locals[:user]
  redirect '/confirm' unless @locals[:user].confirmed?
  content_type 'text/plain'
  "hey: #{params[:keygap]}"
end

get '/id' do
  redirect '/' unless @locals[:user]
  redirect '/confirm' unless @locals[:user].confirmed?
  content_type 'text/plain'
  @locals[:user].item.id.to_s
end

get '/balance' do
  redirect '/' unless @locals[:user]
  redirect '/confirm' unless @locals[:user].confirmed?
  content_type 'text/plain'
  @locals[:user].wallet.balance.to_i
end

post '/id_rsa' do
  redirect '/' unless @locals[:user]
  redirect '/confirm' unless @locals[:user].confirmed?
  content_type 'text/plain'
  keygap = @locals[:keygap].nil? ? params[:keygap] : @locals[:keygap]
  @locals[:user].item.key(keygap).to_s
end

get '/api' do
  redirect '/' unless @locals[:user]
  redirect '/confirm' unless @locals[:user].confirmed?
  haml :api, layout: :layout, locals: merged(
    title: '@' + @locals[:guser][:login] + '/api'
  )
end

post '/do-api' do
  redirect '/' unless @locals[:user]
  redirect '/confirm' unless @locals[:user].confirmed?
  haml :do_api, layout: :layout, locals: merged(
    title: '@' + @locals[:guser][:login] + '/api',
    code: settings.codec.encrypt("#{@locals[:guser][:login]} #{params[:keygap]}")
  )
end

post '/do-api-token' do
  redirect '/' unless @locals[:user]
  redirect '/confirm' unless @locals[:user].confirmed?
  content_type 'text/plain'
  settings.codec.encrypt("#{@locals[:guser][:login]} #{params[:keygap]}")
end

get '/invoice' do
  redirect '/' unless @locals[:user]
  redirect '/confirm' unless @locals[:user].confirmed?
  haml :invoice, layout: :layout, locals: merged(
    title: '@' + @locals[:guser][:login] + '/invoice'
  )
end

get '/log' do
  redirect '/' unless @locals[:user]
  redirect '/confirm' unless @locals[:user].confirmed?
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
  'User-agent: *'
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
  Raven.capture_exception(e)
  haml(
    :error,
    layout: :layout,
    locals: merged(
      title: 'Error',
      error: "#{e.class.name}: #{e.message}\n\t#{e.backtrace.join("\n\t")}"
    )
  )
end

private

def context
  "#{request.ip} #{request.user_agent} #{VERSION}"
end

def merged(hash)
  out = @locals.merge(hash)
  out[:local_assigns] = out
  out
end

def log(user = @locals[:guser][:login])
  TeeLog.new(
    settings.log,
    FileLog.new(File.join(settings.root, ".zold-wts/logs/#{user}"))
  )
end

def user(login)
  User.new(
    login, Item.new(login, settings.dynamo),
    settings.wallets, log: log(login)
  )
end

def latch(login = cookies[:glogin])
  File.join(settings.root, "latch/#{login}")
end

def ops(user, async: true)
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
    settings.config['rewards']['keygap'], @locals[:user].item.id,
    Zold::Amount.new(zld: 8.0), "WTS signup bonus to #{@locals[:guser][:login]}"
  )
end

def pay_hosting_bonuses
  login = settings.config['rewards']['login']
  boss = user(login)
  return unless boss.item.exists?
  require 'zold/commands/remote'
  cmd = Zold::Remote.new(remotes: settings.remotes, log: log(login))
  cmd.run(%w[remote update])
  cmd.run(%w[remote elect --min-score=8]).each do |score|
    ops(boss).pay(
      settings.config['rewards']['keygap'],
      score.invoice,
      Zold::Amount.new(zld: 1.0),
      "Hosting bonus for #{score.host} #{score.port} #{score.value}"
    )
  end
end
