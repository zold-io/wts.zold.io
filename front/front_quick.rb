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

require 'haml'
require 'zold/http'

get '/quick' do
  features('quick')
  flash('/home', 'Please logout first') if @locals[:guser]
  page = params[:haml] || 'default'
  raise WTS::UserError, 'E172: HAML page name is not valid' unless /^[a-zA-Z0-9]{,64}$/.match?(page)
  http = Zold::Http.new(uri: "https://raw.githubusercontent.com/zold-io/quick/master/#{page}.haml").get
  html = Haml::Engine.new(
    if http.status == 200 && http.body.include?('step6')
      http.body
    else
      IO.read(File.join(__dir__, '../views/quick_default.haml'))
    end
  ).render(self)
  haml :quick, layout: :layout, locals: merged(
    page_title: 'Zold: Quick Start',
    header_off: true,
    html: html
  )
end
