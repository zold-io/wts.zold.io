# SPDX-FileCopyrightText: Copyright (c) 2018-2025 Zerocracy
# SPDX-License-Identifier: MIT

require 'zold/commands/create'

get '/push' do
  features('push')
  haml :push, layout: :layout, locals: merged(
    page_title: title('push')
  )
end

get '/do-push' do
  features('push')
  headers['X-Zold-Job'] = job do |_jid, log|
    log.info('Pushing the wallet to the network...')
    unless user.wallet_exists?
      key = user.item.key(keygap)
      Tempfile.open do |f|
        File.write(f, OpenSSL::PKey::RSA.new(key.to_s).public_key.to_pem)
        Zold::Create.new(wallets: settings.wallets, remotes: settings.remotes, log: settings.log).run(
          ['create', user.item.id.to_s, "--network=#{network}", "--public-key=#{f.path}"]
        )
      end
    end
    ops(log: log).push
  end
  flash('/', 'The wallet will be pushed now...')
end
