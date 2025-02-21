# SPDX-FileCopyrightText: Copyright (c) 2018-2025 Zerocracy
# SPDX-License-Identifier: MIT

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
