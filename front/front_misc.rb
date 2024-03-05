# Copyright (c) 2018-2024 Zerocracy
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
  File.read(file)
end
