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
require 'concurrent'
require 'tempfile'
require 'zold/log'
require 'zold/id'
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
require_relative 'objects/file_log'
require_relative 'objects/tee_log'

configure do
  Haml::Options.defaults[:format] = :xhtml
  config = if ENV['RACK_ENV'] == 'test'
    {
      'rewards' => {
        'login' => '0crat',
        'pass' => '?'
      },
      'github' => {
        'client_id' => '?',
        'client_secret' => '?',
        'encryption_secret' => ''
      },
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
  set :remotes, Zold::Remotes.new(File.join(settings.root, '.zold-wts/remotes'))
  set :copies, File.join(settings.root, '.zold-wts/copies')
  set :pool, Concurrent::FixedThreadPool.new(16, max_queue: 64, fallback_policy: :abort)
  set :log, Zold::Log::Quiet.new
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
        settings.config['github']['encryption_secret']
      ).to_user
      @locals[:log] = TeeLog.new(
        settings.log,
        FileLog.new(File.join(settings.root, ".zold-wts/logs/#{@locals[:guser][:login]}"))
      )
      @locals[:user] = user(@locals[:guser][:login])
      @locals[:ops] = ops(@locals[:user])
    rescue OpenSSL::Cipher::CipherError => _
      @locals.delete(:user)
    end
  end
end

get '/github-callback' do
  cookies[:glogin] = GLogin::Cookie::Open.new(
    settings.glogin.user(params[:code]),
    settings.config['github']['encryption_secret']
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

get '/create' do
  redirect '/' unless @locals[:user]
  @locals[:user].create
  pay_bonus
  @locals[:ops].push
  @locals[:log].info("Wallet #{@locals[:user].item.id} created and pushed by @#{@locals[:guser][:login]}\n")
  redirect '/'
end

get '/confirm' do
  redirect '/' unless @locals[:user]
  redirect '/home' if @locals[:user].confirmed?
  haml :confirm, layout: :layout, locals: merged(
    title: '@' + @locals[:guser][:login] + '/pass'
  )
end

get '/do-confirm' do
  redirect '/' unless @locals[:user]
  @locals[:user].confirm(params[:pass])
  @locals[:log].info("Account confirimed for @#{@locals[:guser][:login]}\n")
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
  @locals[:ops].pay(params[:pass], bnf, amount, details)
  @locals[:log].info("Payment made by @#{@locals[:guser][:login]} to #{bnf} for #{amount}\n")
  redirect '/'
end

get '/pull' do
  redirect '/' unless @locals[:user]
  redirect '/confirm' unless @locals[:user].confirmed?
  @locals[:ops].pull
  @locals[:log].info("Wallet #{@locals[:user].item.id} pulled by @#{@locals[:guser][:login]}\n")
  redirect '/'
end

get '/push' do
  redirect '/' unless @locals[:user]
  redirect '/confirm' unless @locals[:user].confirmed?
  @locals[:ops].push
  @locals[:log].info("Wallet #{@locals[:user].item.id} pushed by @#{@locals[:guser][:login]}\n")
  redirect '/'
end

get '/key' do
  redirect '/' unless @locals[:user]
  redirect '/confirm' unless @locals[:user].confirmed?
  haml :key, layout: :layout, locals: merged(
    title: '@' + @locals[:guser][:login] + '/key'
  )
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
  @locals[:log].content
end

get '/remotes' do
  haml :remotes, layout: :layout, locals: merged(
    title: '/remotes'
  )
end

get '/robots.txt' do
  'User-agent: *'
end

get '/version' do
  VERSION
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

def merged(hash)
  out = @locals.merge(hash)
  out[:local_assigns] = out
  out
end

def user(login)
  User.new(
    login, Item.new(login, settings.dynamo),
    settings.wallets, log: @locals[:log]
  )
end

def ops(user, async: true)
  ops = SafeOps.new(
    @locals[:log],
    Ops.new(
      user.item, user,
      settings.wallets,
      settings.remotes,
      settings.copies,
      log: @locals[:log]
    )
  )
  ops = AsyncOps.new(settings.pool, ops) if async
  ops
end

def pay_bonus
  boss = user(settings.config['rewards']['login'])
  ops(boss).pull
  ops(boss).pay(
    settings.config['rewards']['pass'], @locals[:user].item.id,
    Zold::Amount.new(zld: 8.0), 'WTS signup bonus'
  )
end
