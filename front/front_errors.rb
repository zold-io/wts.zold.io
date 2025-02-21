# SPDX-FileCopyrightText: Copyright (c) 2018-2025 Zerocracy
# SPDX-License-Identifier: MIT

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
