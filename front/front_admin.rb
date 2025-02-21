# SPDX-FileCopyrightText: Copyright (c) 2018-2025 Zerocracy
# SPDX-License-Identifier: MIT

require_relative '../objects/item'
require_relative '../objects/user_error'

post '/rename-item' do
  raise WTS::UserError, 'E129: You are not allowed to see this' unless vip?
  from = params[:from]
  to = params[:to]
  item = WTS::Item.new(from, settings.pgsql, log: settings.log)
  item.rename(to)
  flash('/assets', "Item #{from} renamed to #{to}")
end
