# SPDX-FileCopyrightText: Copyright (c) 2018-2025 Zerocracy
# SPDX-License-Identifier: MIT

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
