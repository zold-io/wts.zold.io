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

configure do
  Haml::Options.defaults[:format] = :xhtml
  config = if ENV['RACK_ENV'] == 'test'
    {
      'testing' => true,
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
  set :server_settings, timeout: 25
  set :dynamo, Dynamo.new(config).aws
  set :glogin, GLogin::Auth.new(
    config['github']['client_id'],
    config['github']['client_secret'],
    'https://wts.zold.io/github-callback'
  )
  set :wallets, Zold::Wallets.new('.zold-wts/wallets')
  set :remotes, Zold::Remotes.new('.zold-wts/remotes')
  set :copies, File.join(settings.root, '.zold-wts/copies')
  set :log, Zold::Log::Verbose.new
end

before '/*' do
  @locals = {
    ver: VERSION,
    login_link: settings.glogin.login_uri,
    wallets: settings.wallets,
    remotes: settings.remotes
  }
  cookies[:glogin] = params[:glogin] if params[:glogin]
  if cookies[:glogin]
    begin
      @locals[:guser] = GLogin::Cookie::Closed.new(
        cookies[:glogin],
        settings.config['github']['encryption_secret']
      ).to_user
      @locals[:item] = Item.new(@locals[:guser][:login], settings.dynamo)
      @locals[:user] = User.new(
        @locals[:guser][:login],
        @locals[:item],
        settings.wallets,
        log: settings.log
      )
      @locals[:ops] = Ops.new(
        @locals[:item], @locals[:user],
        settings.wallets,
        settings.remotes,
        settings.copies,
        log: settings.log
      )
      @locals[:user].create
      @locals[:user].push
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
  redirect '/confirm' unless @locals[:user].confirmed?
  haml :home, layout: :layout, locals: merged(
    title: '@' + @locals[:guser][:login],
    start: params[:start] ? Time.parse(params[:start]) : nil
  )
end

get '/confirm' do
  redirect '/' if @locals[:user].confirmed?
  haml :confirm, layout: :layout, locals: merged(
    title: '@' + @locals[:guser][:login] + '/pass'
  )
end

get '/do-confirm' do
  @locals[:user].confirm(params[:pass])
  redirect '/'
end

get '/pay' do
  redirect '/confirm' unless @locals[:user].confirmed?
  haml :pay, layout: :layout, locals: merged(
    title: '@' + @locals[:guser][:login] + '/pay'
  )
end

post '/do-pay' do
  redirect '/confirm' unless @locals[:user].confirmed?
  if params[:bnf] =~ /[a-f0-9]{16}/
    bnf = Zold::Id.new(params[:bnf])
  else
    login = params[:bnf].strip.downcase.gsub(/^@/, '')
    raise "Invalid GitHub user name: '#{params[:bnf]}'" unless login =~ /^[a-z0-9]{3,32}$/
    friend = User.new(
      login,
      Item.new(login, settings.dynamo),
      settings.wallets,
      settings.remotes,
      settings.copies,
      log: settings.log
    )
    friend.create
    bnf = friend.wallet.id
  end
  amount = Zold::Amount.new(zld: params[:amount].to_f)
  settings.log.info('AMOJNT: ' + amount.to_s)
  settings.log.info('hehrejfldskjfkdslj')
  details = params[:details]
  @locals[:ops].pay(params[:pass], bnf, amount, details)
  redirect '/'
end

get '/pull' do
  redirect '/confirm' unless @locals[:user].confirmed?
  @locals[:ops].pull
  redirect '/'
end

get '/push' do
  redirect '/confirm' unless @locals[:user].confirmed?
  @locals[:ops].push
  redirect '/'
end

get '/key' do
  redirect '/confirm' unless @locals[:user].confirmed?
  haml :key, layout: :layout, locals: merged(
    title: '@' + @locals[:guser][:login] + '/key'
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
