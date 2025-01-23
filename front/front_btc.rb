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

require 'glogin'
require 'obk'
require 'retriable_proxy'
require 'sibit'
require 'sibit/bestof'
require 'sibit/bitcoinchain'
require 'sibit/blockchain'
require 'sibit/blockchair'
require 'sibit/btc'
require 'sibit/cex'
require 'sibit/cryptoapis'
require 'sibit/earn'
require 'sibit/fake'
require 'sibit/http'
require 'sibit/json'
require 'syncem'
require_relative '../objects/assets'
require_relative '../objects/coinbase'
require_relative '../objects/referrals'
require_relative '../objects/user_error'

set :codec, GLogin::Codec.new(settings.config['pkey_secret'], base64: true)

def assets(log: settings.log)
  SyncEm.new(
    WTS::Assets.new(
      settings.pgsql,
      log: log,
      codec: settings.codec,
      sibit: sibit(log: log)
    )
  )
end

def coinbase(log: settings.log)
  if settings.config['coinbase']
    SyncEm.new(
      WTS::Coinbase.new(
        settings.config['coinbase']['key'],
        settings.config['coinbase']['secret'],
        settings.config['coinbase']['account'],
        log: log
      )
    )
  else
    WTS::Coinbase::Fake.new
  end
end

def referrals(log: settings.log)
  WTS::Referrals.new(settings.pgsql, log: log)
end

unless ENV['RACK_ENV'] == 'test'
  settings.daemons.start('btc-reconcile', 12 * 60 * 60) do
    assets.reconcile do |address, before, after, hot|
      diff = after - before
      if diff.abs > 10 # smaller changes we just ignore
        settings.telepost.spam(
          diff.positive? ? '📥' : '⚠️',
          "The balance at #{hot ? 'hot' : 'cold'}",
          "[#{address}](https://www.blockchain.com/btc/address/#{address})",
          "was #{diff.positive? ? 'increased' : 'decreased'} by #{diff.abs}",
          "(#{WTS::Dollars.new(diff * price / 100_000_000)}), from #{before} to #{after} satoshi;",
          "our bitcoin assets have [#{assets.balance.round(4)} BTC](https://wts.zold.io/assets)",
          "(#{WTS::Dollars.new(price * assets.balance)})"
        )
      end
    end
  end
  settings.daemons.start('blockchain-lags', 60 * 60) do
    seen = settings.toggles.get('latestblock', '')
    latest = sibit.latest
    diff = sibit.height(latest) - sibit.height(seen)
    if diff > 10
      settings.telepost.spam(
        "⚠️ Our Bitcoin Blockchain monitoring system is behind, for #{diff} blocks!",
        "The most recently seen block is [#{seen}](https://www.blockchain.com/btc/block/#{seen}),",
        "while the latest is [#{latest}](https://www.blockchain.com/btc/block/#{latest});",
        'most probably there is something wrong with [Sibit](https://github.com/yegor256/sibit),',
        'check server logs ASAP!'
      )
    end
  end
  settings.daemons.start('btc-monitor', 5 * 60) do
    seen = settings.toggles.get('latestblock', '')
    seen = assets.monitor(seen, max: 8) do |address, hash, satoshi|
      bitcoin = (satoshi.to_f / 100_000_000).round(8)
      if assets.owned?(address)
        rate = WTS::Rate.new(settings.toggles).to_f
        zld = Zold::Amount.new(zld: bitcoin / rate)
        bnf = user(assets.owner(address))
        boss = user(settings.config['exchange']['login'])
        settings.log.info("Accepting #{bitcoin} bitcoins from #{address} for #{bnf.item.id}...")
        ops(boss, log: settings.log).pull
        begin
          ops(bnf, log: settings.log).pull
          ops(boss, log: settings.log).pay(
            settings.config['exchange']['keygap'],
            bnf.item.id, zld,
            "BTC exchange of #{bitcoin} at #{hash}, rate is #{rate}"
          )
          if referrals.exists?(bnf.login)
            fee = settings.toggles.get('referral-fee', '0.04').to_f
            ops(boss, log: settings.log).pay(
              settings.config['exchange']['keygap'],
              user(referrals.ref(bnf.login)).item.id,
              zld * fee, "#{(fee * 100).round(2)} referral fee for BTC exchange"
            )
          end
          ops(boss, log: settings.log).push
          settings.telepost.spam(
            "👍 In: #{format('%.06f', bitcoin)} BTC (#{WTS::Dollars.new(price * bitcoin)})",
            "[exchanged](https://blog.zold.io/2018/12/09/btc-to-zld.html) to **#{zld}**",
            "by #{title_md(bnf)}",
            "in [#{hash}](https://www.blockchain.com/btc/tx/#{hash.gsub(/:[0-9]+$/, '')})",
            "via [#{address}](https://www.blockchain.com/btc/address/#{address}),",
            "to the wallet [#{bnf.item.id}](http://www.zold.io/ledger.html?wallet=#{bnf.item.id})",
            "with the balance of #{bnf.wallet(&:balance)};",
            "BTC price at the moment of exchange was [#{WTS::Dollars.new(price)}](https://blockchain.info/ticker);",
            "the payer is #{title_md(boss)} with the wallet",
            "[#{boss.item.id}](http://www.zold.io/ledger.html?wallet=#{boss.item.id}),",
            "the remaining balance is #{boss.wallet(&:balance)} (#{boss.wallet(&:txns).count}t);",
            "our bitcoin assets still have [#{assets.balance.round(4)} BTC](https://wts.zold.io/assets)",
            "(#{WTS::Dollars.new(price * assets.balance)})"
          )
        rescue WTS::UserError => e
          raise e unless e.message.start_with?('E186:')
          settings.telepost.spam(
            "👍 Oops: #{format('%.06f', bitcoin)} BTC (#{WTS::Dollars.new(price * bitcoin)})",
            "arrived for #{title_md(bnf)}",
            "in [#{hash}](https://www.blockchain.com/btc/tx/#{hash.gsub(/:[0-9]+$/, '')})",
            "via [#{address}](https://www.blockchain.com/btc/address/#{address}),",
            "to the wallet [#{bnf.item.id}](http://www.zold.io/ledger.html?wallet=#{bnf.item.id})",
            "but the wallet is gone: #{e.message}"
          )
        end
      elsif assets.cold?(address)
        settings.telepost.spam(
          "👍 In: #{format('%.06f', bitcoin)} BTC (#{WTS::Dollars.new(price * bitcoin)}) arrived to",
          "[#{address}](https://www.blockchain.com/btc/address/#{address})",
          "which doesn't belong to anyone,",
          "tx hash was [#{hash}](https://www.blockchain.com/btc/tx/#{hash.gsub(/:[0-9]+$/, '')});",
          'deposited to our fund; many thanks to whoever it was;',
          "our bitcoin assets still have [#{assets.balance.round(4)} BTC](https://wts.zold.io/assets)",
          "(#{WTS::Dollars.new(price * assets.balance)})"
        )
      else
        settings.telepost.spam(
          "📥 #{format('%.06f', bitcoin)} BTC (#{WTS::Dollars.new(price * bitcoin)}) returned back to",
          "[#{address}](https://www.blockchain.com/btc/address/#{address})",
          'as a change from the previous payment,',
          "tx hash is [#{hash}](https://www.blockchain.com/btc/tx/#{hash.gsub(/:[0-9]+$/, '')})",
          "our bitcoin assets still have [#{assets.balance.round(4)} BTC](https://wts.zold.io/assets)",
          "(#{WTS::Dollars.new(price * assets.balance)})"
        )
      end
      assets.see(address, hash)
    end
    raise Error, "Invalid block hash #{seen.inspect}" unless /^[0-9a-f]{64}$/.match?(seen)
    settings.toggles.set('latestblock', seen)
    settings.log.info("We've scanned the entire Blockchain, the latest block is #{seen}")
  end
  settings.daemons.start('btc-from-coinbase', 60 * 60) do
    btc = coinbase.balance
    if btc > 0.01
      address = assets.all(show_empty: true).reject { |a| a[:hot] }.sample[:address]
      amount = [btc * 0.95, 0.1].min.floor(4)
      cid = coinbase.pay(address, amount, 'Going home')
      settings.telepost.spam(
        "📤 Transfer: #{format('%.04f', amount)} BTC was sent from our Coinbase account",
        "to our cold address [#{address}](https://www.blockchain.com/btc/address/#{address});",
        "Coinbase payment ID is #{cid};",
        "our bitcoin assets still have [#{assets.balance.round(4)} BTC](https://wts.zold.io/assets)"
      )
    else
      settings.log.info("We've got just #{btc} BTC in Coinbase, no need to transfer")
    end
  rescue WTS::Coinbase::TryLater => e
    settings.log.debug("Can't send #{btc} BTC from Coinbase, will try later: #{e.message}")
  end
  settings.daemons.start('btc-transfer-to-cold', 60 * 60) do
    hot = assets.all.select { |a| a[:hot] }.map { |a| a[:value] }.inject(&:+).to_f / 100_000_000
    usd = (hot * price).round
    threshold = settings.toggles.get('btc:hot-threshold', '2000').to_i
    if usd <= threshold
      settings.log.info("There are #{hot} BTC in hot addresses (#{WTS::Dollars.new(usd)}), no need to transfer")
    else
      over = usd - threshold + 1
      if over < threshold * 0.2
        settings.log.info("There are #{WTS::Dollars.new(over)} extra in hot addresses, too small to transfer")
      else
        btc = over / price
        colds = assets.all.reject { |a| a[:hot] }
        unless colds.empty?
          address = colds.sample[:address]
          tx = assets.pay(address, (btc * 100_000_000).to_i)
          settings.telepost.spam(
            '📤 Transfer: There were too many "hot" bitcoins in our assets',
            "(#{format('%.04f', hot)} BTC, #{WTS::Dollars.new(usd)}), that's why",
            "we transferred #{format('%.04f', btc)} BTC (#{WTS::Dollars.new(btc * price)}) to the cold address",
            "[#{address}](https://www.blockchain.com/btc/address/#{address})",
            "tx hash is [#{tx}](https://www.blockchain.com/btc/tx/#{tx})"
          )
        end
      end
    end
  end
  settings.daemons.start('btc-rate-notify', 60 * 60) do
    before = settings.toggles.get('recent-zld-rate', '2.03').to_f
    rate = WTS::Rate.new(settings.toggles).to_f
    after = rate * price
    diff = (before - after).abs
    if diff > before * 0.04 || diff > after * 0.04
      settings.toggles.set('recent-zld-rate', after.to_s)
      settings.telepost.spam(
        "#{after > before ? '📈' : '📉'} The rate of ZLD moved #{after > before ? 'UP' : 'DOWN'}",
        "from #{WTS::Dollars.new(before)} to #{WTS::Dollars.new(after)},",
        "which is #{after > before ? '+' : ''}#{format('%.02f', 100.0 * (after - before) / before)}%;",
        "the [price](https://coinmarketcap.com/currencies/bitcoin/) of Bitcoin is #{WTS::Dollars.new(price)};",
        'more details [here](https://wts.zold.io/rate);',
        'it is time to buy, [click here](https://wts.zold.io/quick)!'
      )
    end
  end
  settings.daemons.start('btc-hot-deficit-notify', 12 * 60 * 60) do
    hot = assets.all.select { |a| a[:hot] }.map { |a| a[:value] }.inject(&:+).to_f / 100_000_000
    usd = (hot * price).round
    if usd < settings.toggles.get('btc:deficit-threshold', '1000').to_i
      settings.telepost.spam(
        "⚠️ There are just #{format('%.04f', hot)} BTC (#{WTS::Dollars.new(usd)}) left in",
        'our hot Bitcoin addresses; this may not be enough for our daily operations;',
        'consider transferring some cold [assets](https://wts.zold.io/assets) back to hot'
      )
    end
  end
end

get '/funded' do
  raise WTS::UserError, 'E104: Amount parameter is mandatory' unless params[:amount]
  usd = params[:amount].to_f
  raise WTS::UserError, 'E105: The amount can\'t be zero' if usd.zero?
  zerocrat = user(settings.config['zerocrat']['login'])
  unless user.login == zerocrat.login || vip?
    raise WTS::UserError, "E191: Only Zerocrat and VIP users are allowed to do this, you are #{user.login}"
  end
  boss = user(settings.config['exchange']['login'])
  btc = usd / price
  rate = WTS::Rate.new(settings.toggles).to_f
  zld = Zold::Amount.new(zld: btc / rate)
  job(boss, exclusive: true) do |jid, log|
    log.info("Buying bitcoins for #{WTS::Dollars.new(usd)} at Coinbase...")
    if settings.toggles.get('coinbase-buy', 'no') == 'yes'
      ops(boss, log: log).pull
      ops(zerocrat, log: log).pull
      cid = coinbase(log: log).buy(usd)
      txn = ops(boss, log: log).pay(
        settings.config['exchange']['keygap'],
        zerocrat.item.id,
        zld,
        "Purchased #{btc} BTC for #{usd} USD at Coinbase"
      )
      settings.telepost.spam(
        "✌️ Buy: **#{btc.round(4)}** BTC were purchased",
        "for #{WTS::Dollars.new(usd)} at [Coinbase](https://coinbase.com),",
        "#{zld} were deposited to the wallet",
        "[#{zerocrat.item.id}](http://www.zold.io/ledger.html?wallet=#{zerocrat.item.id})",
        "owned by [#{zerocrat.login}](https://github.com/#{zerocrat.login})",
        "with the remaining balance of #{zerocrat.wallet(&:balance)};",
        "BTC price at the time of exchange was [#{WTS::Dollars.new(price)}](https://blockchain.info/ticker);",
        "zolds were sent by [#{zerocrat.login}](https://github.com/#{zerocrat.login})",
        "from the wallet [#{boss.item.id}](http://www.zold.io/ledger.html?wallet=#{boss.item.id})",
        "with the remaining balance of #{boss.wallet(&:balance)} (#{boss.wallet(&:txns).count}t);",
        "Zold transaction ID is #{txn.id};",
        "Coinbase payment ID is #{cid};",
        "our bitcoin assets still have [#{assets.balance.round(4)} BTC](https://wts.zold.io/assets)",
        job_link(jid)
      )
    else
      settings.telepost.spam(
        "⚠️ Would be great to purchase **#{btc.round(4)}** BTC for #{WTS::Dollars.new(usd)}",
        'at [Coinbase](https://coinbase.com), but we aren\'t doing it,',
        'because the `coinbase-buy` toggle is turned OFF;',
        "our bitcoin assets still have [#{assets.balance.round(4)} BTC](https://wts.zold.io/assets)",
        job_link(jid)
      )
    end
  end
  'OK, thanks'
end

post '/add-asset' do
  raise WTS::UserError, 'E129: You are not allowed to see this' unless vip?
  address = params[:address]
  assets.add_cold(address)
  flash('/assets', "Cold asset added at #{address}")
end

get '/btc-to-zld' do
  features('btc', 'buy-btc')
  address = assets.acquire(confirmed_user.login) do |u, a, k|
    settings.telepost.spam(
      "✍️ A new Bitcoin address [#{a}](https://www.blockchain.com/btc/address/#{a}) generated",
      u.nil? ? 'as a storage for change' : 'by a user',
      "with this private key (it is encrypted):\n\n```\n#{k.scan(/.{20}/).join("\n")}\n```"
    )
  end
  headers['X-Zold-BtcAddress'] = address
  haml :btc_to_zld, layout: :layout, locals: merged(
    page_title: title('buy'),
    address: address,
    rate: WTS::Rate.new(settings.toggles).to_f
  )
end

get '/zld-to-btc' do
  features('btc', 'sell-btc')
  haml :zld_to_btc, layout: :layout, locals: merged(
    page_title: title('sell'),
    user: confirmed_user,
    rate: WTS::Rate.new(settings.toggles).to_f,
    fee: exfee,
    price: price,
    btc_fee: sibit.fees[:L] * 250.0 / 100_000_000,
    available: assets.balance(hot_only: true)
  )
end

post '/do-zld-to-btc' do
  features('sell', 'sell-btc')
  raise WTS::UserError, 'E141: Amount is not provided' if params[:amount].nil?
  raise WTS::UserError, 'E142: Bitcoin address is not provided' if params[:btc].nil?
  raise WTS::UserError, 'E143: Keygap is not provided' if params[:keygap].nil?
  amount = Zold::Amount.new(zld: params[:amount].to_f)
  min = Zold::Amount.new(zld: settings.toggles.get('min-out-btc', '0').to_f)
  raise WTS::UserError, "E195: The amount #{amount} is too small, smaller than #{min}" if amount < min
  address = params[:btc].strip
  raise WTS::UserError, "E144: Bitcoin address is not valid: #{address.inspect}" unless address =~ /^[a-zA-Z0-9]+$/
  raise WTS::UserError, 'E145: Bitcoin address must start with 1, 3 or bc1' unless address =~ /^(1|3|bc1)/
  balance = confirmed_user.wallet(&:balance)
  raise WTS::UserError, "E146: You don't have enough to send #{amount}" if balance < amount
  maxout = settings.toggles.get('maxout', '1.0').to_f
  raise WTS::UserError, "E146: For your safety, send less than #{balance * maxout}" if balance * maxout < amount
  if settings.toggles.get('ban:do-sell').split(',').include?(user.login)
    settings.telepost.spam(
      "⚠️ The user #{title_md} from #{anon_ip} is trying to sell #{amount},",
      'while their account is banned via "ban:do-sell";',
      "the balance of the user is #{balance}",
      "at the wallet [#{user.item.id}](http://www.zold.io/ledger.html?wallet=#{user.item.id})"
    )
    raise WTS::UserError, 'E147: Your account is not allowed to sell any ZLD at the moment, email us'
  end
  limits = settings.toggles.get('limits', '64/128/256')
  unless settings.payouts.allowed?(user.login, amount, limits) || vip?
    consumed = settings.payouts.consumed(user.login)
    settings.telepost.spam(
      "⚠️ The user #{title_md} from #{anon_ip} with #{amount} payment just attempted to go",
      "over their account limits: \"#{consumed}\", while allowed thresholds are \"#{limits}\";",
      "the balance of the user is #{balance}",
      "at the wallet [#{user.item.id}](http://www.zold.io/ledger.html?wallet=#{user.item.id})"
    )
    raise WTS::UserError, "E148: With #{amount} you are going over your limits, #{consumed} were sold already, \
while we allow one user to sell up to #{limits} (daily/weekly/monthly)"
  end
  limits = settings.toggles.get('system-limits', '512/2048/8196')
  unless settings.payouts.safe?(amount, limits) || vip?
    consumed = settings.payouts.system_consumed
    settings.telepost.spam(
      "⚠️ The user #{title_md} from #{anon_ip} with #{amount} payment just attempted to go",
      "over our limits: \"#{consumed}\", while allowed thresholds are \"#{limits}\";",
      "the balance of the user is #{balance}",
      "at the wallet [#{user.item.id}](http://www.zold.io/ledger.html?wallet=#{user.item.id})"
    )
    raise WTS::UserError, "E149: With #{amount} you are going over our limits, #{consumed} were sold by ALL \
users of WTS, while our limits are #{limits} (daily/weekly/monthly), sorry about this :("
  end
  rate = WTS::Rate.new(settings.toggles).to_f
  bitcoin = (amount.to_zld(8).to_f * rate).round(8)
  fee = sibit(log: settings.log).fees[:XL] * 180.0 / 100_000_000
  if bitcoin + fee > assets.balance(hot_only: true)
    raise WTS::UserError, "E198: The amount #{amount} BTC is too big for us, \
we've got only #{format('%.04f', assets.balance(hot_only: true))} left in hot addresses; \
we will also have to pay around #{format('%.04f', fee)} in transaction fees; \
try to contact us in our Telegram group and notify the admin"
  end
  boss = user(settings.config['exchange']['login'])
  rewards = user(settings.config['rewards']['login'])
  job(exclusive: true) do |jid, log|
    log.info("Sending #{bitcoin} bitcoins to #{address}...")
    f = exfee
    ops(log: log).pull
    ops(rewards, log: log).pull
    ops(boss, log: log).pull
    ops(log: log).pay(
      keygap,
      boss.item.id,
      amount * (1.0 - f),
      "ZLD exchange to #{bitcoin} BTC at #{address}, rate is #{rate}, fee is #{f}, job ID is #{jid}"
    )
    ops(log: log).pay(
      keygap,
      rewards.item.id,
      amount * f,
      "Fee for exchange of #{bitcoin} BTC at #{address}, rate is #{rate}, fee is #{f}"
    )
    ops(log: log).push
    tx = assets(log: log).pay(address, (bitcoin * 100_000_000 * (1 - fee)).round)
    log.info("Bitcoin transaction hash is #{tx}")
    settings.payouts.add(
      user.login, user.item.id, amount,
      "#{bitcoin} BTC sent to #{address} in tx hash #{tx}; \
the price was #{WTS::Dollars.new(price)}/BTC; the fee was #{(f * 100).round(2)}%, \
bitcoin assets still have #{assets.balance.round(4)} BTC"
    )
    settings.telepost.spam(
      "😢 Out: #{amount} [exchanged](https://blog.zold.io/2018/12/09/btc-to-zld.html) to #{bitcoin} BTC",
      "by #{title_md} from #{anon_ip}",
      "from the wallet [#{user.item.id}](http://www.zold.io/ledger.html?wallet=#{user.item.id})",
      "with the remaining balance of #{user.wallet(&:balance)}",
      "to bitcoin address [#{address}](https://www.blockchain.com/btc/address/#{address});",
      "tx hash is [#{tx}](https://www.blockchain.com/btc/tx/#{tx});",
      "BTC price at the time of exchange was [#{WTS::Dollars.new(price)}](https://blockchain.info/ticker);",
      "our bitcoin assets still have [#{assets.balance.round(4)} BTC](https://wts.zold.io/assets)",
      "(worth about #{WTS::Dollars.new(assets.balance * price)});",
      "zolds were deposited to [#{boss.item.id}](http://www.zold.io/ledger.html?wallet=#{boss.item.id})",
      "of [#{boss.login}](https://github.com/#{boss.login}),",
      "the balance is #{boss.wallet(&:balance)} (#{boss.wallet(&:txns).count}t);",
      "the exchange fee of #{amount * f}",
      "was deposited to [#{rewards.item.id}](http://www.zold.io/ledger.html?wallet=#{rewards.item.id})",
      "of [#{rewards.login}](https://github.com/#{rewards.login}),",
      "the balance is #{rewards.wallet(&:balance)} (#{rewards.wallet(&:txns).count}t);",
      job_link(jid)
    )
    if boss.wallet(&:txns).count > 1000
      ops(boss, log: log).migrate(settings.config['exchange']['keygap'])
      settings.telepost.spam(
        'The office wallet has been migrated to a new place',
        "[#{boss.item.id}](http://www.zold.io/ledger.html?wallet=#{boss.item.id}),",
        "the balance is #{boss.wallet(&:balance)};",
        job_link(jid)
      )
    end
  end
  flash('/zld-to-btc', "We took #{amount} from your wallet and will send you #{bitcoin} BTC soon")
end

post '/cold-to-hot' do
  raise WTS::UserError, 'E129: You are not allowed to use this, only yegor256' unless user.login == 'yegor256'
  btc = params[:amount].to_f
  raise WTS::UserError, "E219: The amount #{btc} BTC is too small" if btc < 0.01
  address = params[:address].strip
  job(exclusive: true) do |jid, log|
    log.info("Sending cold #{btc} BTC from #{address} to a random hot one...")
    hot = assets(log: log).acquire
    tx = sibit(log: log).pay(
      (btc * 100_000_000).round,
      '-XL',
      { address => params[:pkey].strip },
      hot,
      address
    )
    assets(log: log).set(address, 0)
    settings.telepost.spam(
      "🛠 Transfer: #{format('%.04f', btc)} BTC (#{WTS::Dollars.new(btc * price)}) transferred from a cold address",
      "[#{address}](https://www.blockchain.com/btc/address/#{address});",
      "to the hot one [#{hot}](https://www.blockchain.com/btc/address/#{hot})",
      "by #{title_md} from #{anon_ip};",
      "tx hash is [#{tx}](https://www.blockchain.com/btc/tx/#{tx});",
      "our bitcoin assets still have [#{assets.balance.round(4)} BTC](https://wts.zold.io/assets)",
      "(worth about #{WTS::Dollars.new(assets.balance * price)});",
      job_link(jid)
    )
  end
  flash('/assets', 'Cold bitcoins will be trasferred to a hot address soon')
end

post '/cold-out' do
  raise WTS::UserError, 'E129: You are not allowed to use this, only yegor256' unless user.login == 'yegor256'
  btc = params[:amount].to_f
  raise WTS::UserError, "E219: The amount #{btc} BTC is too small" if btc < 0.01
  raise WTS::UserError, "E220: The amount #{btc} BTC is too large" if btc > 0.2
  address = params[:address].strip
  target = params[:target].strip
  job(exclusive: true) do |jid, log|
    log.info("Sending cold #{btc} BTC from #{address} to #{target}...")
    tx = sibit(log: log).pay(
      (btc * 100_000_000).round,
      'L',
      { address => params[:pkey].strip },
      target,
      address
    )
    assets(log: log).set(address, 0)
    settings.telepost.spam(
      "Out: #{format('%.04f', btc)} BTC (#{WTS::Dollars.new(btc * price)}) was sent from a cold address",
      "[#{address}](https://www.blockchain.com/btc/address/#{address})",
      "to a foreign one [#{target}](https://www.blockchain.com/btc/address/#{target})",
      "by #{title_md} from #{anon_ip};",
      "tx hash is [#{tx}](https://www.blockchain.com/btc/tx/#{tx});",
      "our bitcoin assets still have [#{assets.balance.round(4)} BTC](https://wts.zold.io/assets)",
      "(worth about #{WTS::Dollars.new(assets.balance * price)});",
      job_link(jid)
    )
  end
  flash('/assets', 'Cold bitcoins will be trasferred soon')
end

get '/assets' do
  features('see-assets')
  haml :assets, layout: :layout, locals: merged(
    page_title: 'Assets',
    assets: assets.all(show_empty: params[:empty]),
    balance: assets.balance,
    price: price,
    limit: assets.balance(hot_only: true)
  )
end

get '/assets-private-keys' do
  raise WTS::UserError, 'E129: You are not allowed to see this, only yegor256' unless user.login == 'yegor256'
  content_type 'text/plain'
  assets.disclose.map { |a| "#{a[:address]}: #{a[:pvt]} / #{a[:value]}s #{a[:login]}" }.join("\n")
end

post '/decrypt-pkey' do
  raise WTS::UserError, 'E129: You are not allowed to see this, only yegor256' unless user.login == 'yegor256'
  text = params[:text]
  content_type 'text/plain'
  settings.codec.decrypt(text)
end

get '/referrals' do
  features('see-referrals')
  haml :referrals, layout: :layout, locals: merged(
    page_title: title('referrals'),
    referrals: referrals,
    fee: settings.toggles.get('referral-fee', '0.04').to_f,
    login_alias: WTS::Referrals::Crypt.new.encode(user.login)
  )
end

def price
  settings.zache.get(:price, lifetime: 5 * 60) { assets.price }
end

def register_referral(login)
  return unless cookies[:ref] && !referrals.exists?(login)
  referrals.register(
    login, cookies[:ref],
    source: cookies[:utm_source], medium: cookies[:utm_medium], campaign: cookies[:utm_campaign]
  )
end

def sibit(log: settings.log)
  api = [Sibit::Fake.new]
  if ENV['RACK_ENV'] != 'test'
    http = Sibit::Http.new
    api = settings.toggles.get('sibit:api', 'blockchain').split(',').map do |a|
      case a
      when 'earn'
        Sibit::Earn.new(log: log, http: http)
      when 'cryptoapis'
        Sibit::Cryptoapis.new(settings.config['cryptoapis_key'], log: log, http: http)
      when 'blockchair'
        Sibit::Blockchair.new(key: settings.config['blockchair_key'], log: log, http: http)
      when 'bitcoinchain'
        Sibit::Bitcoinchain.new(log: log, http: http)
      when 'btc'
        Sibit::Btc.new(log: log, http: http)
      when 'cex'
        Sibit::Cex.new(log: log, http: http)
      when 'blockchain'
        Sibit::Blockchain.new(log: log, http: http)
      else
        raise "Unknown API #{a}"
      end
    end
    api = api.map { |a| RetriableProxy.for_object(a, on: Sibit::Error) }
  end
  Obk.new(Sibit.new(log: log, api: Sibit::BestOf.new(api, log: log)), pause: 2 * 1000)
end
