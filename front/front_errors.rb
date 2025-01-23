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

not_found do
  status 404
  content_type 'text/html', charset: 'utf-8'
  haml :not_found, layout: :layout, locals: merged(
    page_title: 'Page not found'
  )
end

error do
  e = env['sinatra.error']
  if e.is_a?(WTS::UserError)
    settings.log.error("#{request.url}: #{e.message}")
    body(Backtrace.new(e).to_s)
    headers['X-Zold-Error'] = e.message[0..256]
    if params[:noredirect]
      content_type 'text/plain', charset: 'utf-8'
      return Backtrace.new(e).to_s
    end
    flash('/', e.message, error: true)
  end
  status 503
  Raven.capture_exception(e, extra: { 'request_url' => request.url })
  if params[:noredirect]
    Backtrace.new(e).to_s
  else
    haml :error, layout: :layout, locals: merged(
      page_title: 'Error',
      error: Backtrace.new(e).to_s
    )
  end
end
