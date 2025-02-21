# SPDX-FileCopyrightText: Copyright (c) 2018-2025 Zerocracy
# SPDX-License-Identifier: MIT

unless ENV['RACK_ENV'] == 'test'
  settings.daemons.start('auto-pull', 60) do
    settings.pgsql.exec('SELECT login FROM item WHERE touched > NOW() - INTERVAL \'30 DAYS\'').each do |r|
      u = user(r['login'])
      next if File.exist?(latch(u.login))
      next if u.wallet_exists?
      job(u) do |_jid, log|
        log.info("Auto-pulling wallet #{u.item.id}...")
        ops(u, log: log).pull
      end
    end
  end
end
