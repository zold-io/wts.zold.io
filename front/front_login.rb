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

require 'aws-sdk-sns'
require 'glogin'
require_relative '../objects/mcodes'
require_relative '../objects/tokens'
require_relative '../objects/smss'
require_relative '../objects/user_error'

set :tokens, WTS::Tokens.new(settings.pgsql, log: settings.log)
set :mcodes, WTS::Mcodes.new(settings.pgsql, log: settings.log)
if settings.config['sns']
  set :smss, WTS::Smss.new(
    settings.pgsql,
    Aws::SNS::Client.new(
      region: settings.config['sns']['region'],
      access_key_id: settings.config['sns']['key'],
      secret_access_key: settings.config['sns']['secret']
    ),
    log: settings.log
  )
else
  set :smss, WTS::Smss::Fake.new
end

before '/*' do
  @locals = {
    ver: WTS::VERSION,
    iri: Iri.new(request.url),
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
  @locals[:guser] = Zold::Id::ROOT.to_s if params[:glogin] == Zold::Id::ROOT.to_s
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

get '/github-callback' do
  error(400) if params[:code].nil?
  c = GLogin::Cookie::Open.new(
    settings.glogin.user(params[:code]),
    settings.config['github']['encryption_secret'],
    context
  )
  unless known?(c.login) || vip?(c.login)
    allowed = settings.toggles.get('allow').strip.split(',')
    unless allowed.include?(c.login.downcase)
      raise WTS::UserError, "E103: #{c.login.inspect} doesn't work in Zerocracy, can't login via GitHub, \
use mobile phone (see KYC section in our Terms of Use) /#{allowed.count}"
    end
  end
  cookies[:glogin] = c.to_s
  register_referral(c.login)
  flash('/', "You have been logged in as @#{c.login}")
end

get '/logout' do
  cookies.delete(:glogin)
  cookies.delete(:wts)
  flash('/', 'You have been logged out')
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

get '/confirm' do
  raise WTS::UserError, 'E106: You have done this already, your keygap has been generated' if user.confirmed?
  haml :confirm, layout: :layout, locals: merged(
    page_title: title('keygap')
  )
end

get '/confirmed' do
  content_type 'text/plain'
  user.confirmed? ? 'yes' : 'no'
end

get '/do-confirm' do
  raise WTS::UserError, 'E107: You have done this already, your keygap has been generated' if user.confirmed?
  user.confirm(params[:keygap])
  flash('/', 'The account has been confirmed')
end

get '/mobile/send' do
  features('api')
  phone = params[:phone]
  raise WTS::UserError, 'E159: Mobile phone number is required' if phone.nil?
  raise WTS::UserError, 'E160: Phone number can\'t be empty, format it according to E.164' if phone.empty?
  unless /^[0-9]+$/.match?(phone)
    raise WTS::UserError, "E161: Invalid phone #{phone.inspect}, digits only allowed (E.164)"
  end
  raise WTS::UserError, 'E161: The phone shouldn\'t start with zeros' if /^0+/.match?(phone)
  raise WTS::UserError, "E162: The phone number #{phone.inspect} is too short" if phone.length < 6
  raise WTS::UserError, "E163: The phone number #{phone.inspect} is too long" if phone.length > 14
  phone = phone.to_i
  mcode = rand(1000..9999)
  if settings.mcodes.exists?(phone)
    mcode = settings.mcodes.get(phone)
  else
    settings.mcodes.set(phone, mcode)
  end
  cid = settings.smss.deliver(phone, "Your authorization code for wts.zold.io is: #{mcode}")
  if params[:noredirect]
    content_type 'text/plain'
    return cid.to_s
  end
  flash("/mobile_token?phone=#{phone}", "The SMS ##{cid} was sent with the auth code")
end

get '/mobile/token' do
  features('api')
  phone = params[:phone]
  raise WTS::UserError, 'E164: Mobile phone number is required' if phone.nil?
  raise WTS::UserError, 'E165: Phone number can\'t be empty, format it according to E.164' if phone.empty?
  unless /^[0-9]+$/.match?(phone)
    raise WTS::UserError, "E166: Invalid phone #{phone.inspect}, digits only allowed (E.164)"
  end
  phone = phone.to_i
  mcode = params[:code].strip
  raise WTS::UserError, 'E167: Mobile confirmation code can\'t be empty' if mcode.empty?
  raise WTS::UserError, "E168: Invalid code #{mcode.inspect}, must be four digits" unless /^[0-9]{4}$/.match?(mcode)
  raise WTS::UserError, 'E169: Mobile code mismatch' unless settings.mcodes.get(phone) == mcode.to_i
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
