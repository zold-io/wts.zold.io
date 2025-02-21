# SPDX-FileCopyrightText: Copyright (c) 2018-2025 Zerocracy
# SPDX-License-Identifier: MIT

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
