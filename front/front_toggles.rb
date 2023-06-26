# Copyright (c) 2018-2023 Zold
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

require_relative '../objects/toggles'
require_relative '../objects/user_error'

set :toggles, WTS::Toggles.new(settings.pgsql, log: settings.log)

get '/toggles' do
  raise WTS::UserError, 'E170: You are not allowed to see this' unless vip?
  haml :toggles, layout: :layout, locals: merged(
    page_title: 'Toggles',
    toggles: settings.toggles
  )
end

post '/set-toggle' do
  raise WTS::UserError, 'E171: You are not allowed to see this' unless vip?
  key = params[:key].strip
  value = params[:value].strip
  settings.toggles.set(key, value)
  settings.telepost.spam(
    "The toggle \"`#{key}`\" was set to \"`#{value}`\"",
    "by #{title_md} from #{anon_ip}"
  )
  flash('/toggles', "The feature toggle #{key.inspect} re/set")
end
