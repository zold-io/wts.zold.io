# Copyright (c) 2018-2020 Zold
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

require 'zold'
require_relative '../objects/gl'
require_relative '../objects/payables'
require_relative '../objects/callbacks'
require_relative '../objects/user_error'

set :gl, WTS::Gl.new(settings.pgsql, log: settings.log)
set :payables, WTS::Payables.new(settings.pgsql, settings.remotes, log: settings.log)
set :callbacks, WTS::Callbacks.new(settings.pgsql, log: settings.log)

settings.daemons.start('scan-general-ledger') do
  settings.gl.scan(settings.remotes) do |t|
    settings.log.info("A new transaction #{t[:tid]} added to the General Ledger \
for #{t[:amount].to_zld(6)} from #{t[:source]} to #{t[:target]} with details #{t[:details].inspect} \
and dated #{t[:date].utc.iso8601}")
    settings.callbacks.match(t[:tid], t[:target], t[:prefix], t[:details]) do |c, mid|
      settings.telepost.spam(
        "The callback no.#{c[:id]} owned by #{title_md(user(c[:login]))} just matched",
        "in [#{c[:wallet]}](http://www.zold.io/ledger.html?wallet=#{c[:wallet]})",
        "with prefix `#{c[:prefix]}` and details #{t[:details].inspect}, match ID is #{mid},",
        "TID is #{t[:tid]}"
      )
    end
  end
end

settings.daemons.start('payables', 10 * 60) do
  settings.payables.remove_old
  settings.payables.discover
  settings.payables.update
  settings.payables.remove_banned
end

settings.daemons.start('callbacks-ping') do
  settings.callbacks.ping do |login, id, pfx, regexp|
    ops(user(login)).pull(id)
    settings.wallets.acq(id) do |wallet|
      wallet.txns.select do |t|
        t.prefix == pfx && regexp.match?(t.details)
      end
    end
  end
end

settings.daemons.start('callbacks-clean') do
  settings.callbacks.repeat_succeeded do |c|
    settings.telepost.spam(
      "The callback no.#{c[:id]} owned by #{title_md(user(c[:login]))} was repeated, since it was delivered;",
      "the wallet was [#{c[:wallet]}](http://www.zold.io/ledger.html?wallet=#{c[:wallet]})",
      "the prefix was `#{c[:prefix]}` and the regexp was `#{c[:regexp].inspect}`"
    )
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

get '/callbacks' do
  features('api')
  haml :callbacks, layout: :layout, locals: merged(
    page_title: title('callbacks'),
    callbacks: settings.callbacks
  )
end

get '/callback-restart' do
  features('api')
  settings.callbacks.restart(params[:id].to_i)
  flash('/callbacks', 'The callback was cleaned, will be matched again soon')
end

get '/null' do
  content_type 'text/plain'
  'OK'
end

get '/wait-for' do
  features('api')
  wallet = params[:wallet] || confirmed_user.item.id.to_s
  prefix = params[:prefix]
  raise WTS::UserError, 'E120: The parameter "prefix" is mandatory' if prefix.nil?
  regexp = /^.*$/
  begin
    regexp = Regexp.new(params[:regexp]) if params[:regexp]
  rescue RegexpError => e
    raise WTS::UserError, "E205: Regular expression #{params[:regexp].inspect} is not valid: #{e.message}"
  end
  uri = URI(params[:uri])
  raise WTS::UserError, 'E121: The parameter "uri" is mandatory' if uri.nil?
  id = settings.callbacks.add(
    user.login, Zold::Id.new(wallet), prefix, regexp, uri,
    params[:token] || 'none',
    repeat: params[:repeat] ? true : false,
    forever: params[:forever] ? true : false
  )
  settings.telepost.spam(
    "New callback no.#{id} created by #{title_md} from #{anon_ip}",
    "for the wallet [#{wallet}](http://www.zold.io/ledger.html?wallet=#{wallet}),",
    "prefix `#{prefix}`, and regular expression `#{safe_md(regexp.to_s)}`,",
    "repeat=#{params[:repeat]}, forever=#{params[:forever]}"
  )
  content_type 'text/plain'
  id.to_s
end

get '/payables' do
  haml :payables, layout: :layout, locals: merged(
    page_title: 'Payables',
    rate: WTS::Rate.new(settings.toggles).to_f,
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
rescue Zold::Txn::CantParseTime => e
  raise WTS::UserError, e.message
end
