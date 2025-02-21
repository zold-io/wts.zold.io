# SPDX-FileCopyrightText: Copyright (c) 2018-2025 Zerocracy
# SPDX-License-Identifier: MIT

get '/migrate' do
  features('migrate')
  haml :migrate, layout: :layout, locals: merged(
    page_title: title('migrate')
  )
end

get '/do-migrate' do
  features('migrate')
  headers['X-Zold-Job'] = job do |jid, log|
    origin = user.item.id
    ops(log: log).migrate(keygap)
    settings.telepost.spam(
      "The wallet [#{origin}](http://www.zold.io/ledger.html?wallet=#{origin})",
      "with #{settings.wallets.acq(origin, &:txns).count} transactions",
      "and #{user.wallet(&:balance)}",
      "has been migrated to a new wallet [#{user.item.id}](http://www.zold.io/ledger.html?wallet=#{user.item.id})",
      "by #{title_md} from #{anon_ip}",
      job_link(jid)
    )
  end
  flash('/', 'You got a new wallet ID, your funds will be transferred soon...')
end
