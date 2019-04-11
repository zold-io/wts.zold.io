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
