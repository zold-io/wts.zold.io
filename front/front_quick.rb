# Copyright (c) 2018-2025 Zerocracy
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

require 'haml'
require 'zold/http'

get '/quick' do
  flash('/home', 'Please logout first') if @locals[:guser]
  features('quick')
  page = (params[:haml] || 'default').strip
  raise WTS::UserError, 'E172: HAML page name is not valid' unless /^[a-zA-Z0-9]{,64}$/.match?(page)
  uri = "https://raw.githubusercontent.com/zold-io/quick/master/#{page}.haml"
  http = Zold::Http.new(uri: uri).get
  body = ''
  if http.status == 200 && http.body.include?('step6')
    body = http.body
    settings.log.debug("HAML template #{page} found at #{uri}: #{body.length} bytes")
  else
    body = File.read(File.join(__dir__, '../views/quick_default.haml'))
    settings.log.debug("HAML template #{page} not found at #{uri}, using default of #{body.length} bytes")
  end
  body.force_encoding('utf-8')
  html = Haml::Engine.new(body).render(self)
  haml :quick, layout: :layout, locals: merged(
    page_title: 'Zold: Quick Start',
    header_off: true,
    html: html
  )
end
