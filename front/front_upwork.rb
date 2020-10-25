# Copyright (c) 2018-2020 Zold
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

require 'zold'
require 'syncem'
require_relative '../objects/upwork'
require_relative '../objects/user_error'

def upwork(log: settings.log)
  SyncEm.new(
    WTS::Upwork.new(
      {
        'consumer_key' => settings.config['upwork']['consumer_key'],
        'consumer_secret' => settings.config['upwork']['consumer_secret'],
        'access_token' => settings.config['upwork']['access_token'],
        'access_secret' => settings.config['upwork']['access_secret']
      },
      settings.config['upwork']['team'],
      log: log
    )
  )
end

get '/zld-to-upwork' do
  features('sell', 'sell-upwork')
  raise WTS::UserError, 'E207: You have to work in Zerocracy in order to cash out to UpWork' unless known?
  raise WTS::UserError, 'E208: You have to be identified in Zerocracy' unless kyc?
  haml :zld_to_upwork, layout: :layout, locals: merged(
    page_title: title('upwork'),
    rate: WTS::Rate.new(settings.toggles).to_f,
    price: price,
    fee: exfee,
    user: confirmed_user
  )
end

post '/do-zld-to-upwork' do
  features('sell-upwork', 'sell')
  raise WTS::UserError, 'E209: You have to work in Zerocracy in order to cash out to UpWork' unless known?
  raise WTS::UserError, 'E210: You have to be identified in Zerocracy' unless kyc?
  raise WTS::UserError, 'E211: Amount is not provided' if params[:amount].nil?
  raise WTS::UserError, 'E212: Email address is not provided' if params[:email].nil?
  raise WTS::UserError, 'E213: Keygap is not provided' if params[:keygap].nil?
  amount = Zold::Amount.new(zld: params[:amount].to_f)
  min = Zold::Amount.new(zld: settings.toggles.get('min-out-upwork', '0').to_f)
  raise WTS::UserError, "E214: The amount #{amount} is too small, smaller than #{min}" if amount < min
  contract = params[:contract].strip
  raise WTS::UserError, "E215: You don't have enough to send #{amount}" if confirmed_user.wallet(&:balance) < amount
  if settings.toggles.get('ban:do-sell').split(',').include?(user.login)
    settings.telepost.spam(
      "⚠️ The user #{title_md} from #{anon_ip} is trying to send #{amount} to UpWork,",
      'while their account is banned via "ban:do-sell";',
      "the balance of the user is #{user.wallet(&:balance)}",
      "at the wallet [#{user.item.id}](http://www.zold.io/ledger.html?wallet=#{user.item.id})"
    )
    raise WTS::UserError, 'E216: Your account is not allowed to sell any ZLD at the moment, email us'
  end
  limits = settings.toggles.get('limits', '64/128/256')
  unless settings.payouts.allowed?(user.login, amount, limits) || vip?
    consumed = settings.payouts.consumed(user.login)
    settings.telepost.spam(
      "⚠️ The user #{title_md} from #{anon_ip} with #{amount} payment to UpWork just attempted to go",
      "over their account limits: \"#{consumed}\", while allowed thresholds are \"#{limits}\";",
      "the balance of the user is #{user.wallet(&:balance)}",
      "at the wallet [#{user.item.id}](http://www.zold.io/ledger.html?wallet=#{user.item.id})"
    )
    raise WTS::UserError, "E217: With #{amount} you are going over your limits, #{consumed} were sold already, \
while we allow one user to sell up to #{limits} (daily/weekly/monthly)"
  end
  limits = settings.toggles.get('system-limits', '512/2048/8196')
  unless settings.payouts.safe?(amount, limits) || vip?
    consumed = settings.payouts.system_consumed
    settings.telepost.spam(
      "⚠️ The user #{title_md} from #{anon_ip} with #{amount} payment to UpWork just attempted to go",
      "over our limits: \"#{consumed}\", while allowed thresholds are \"#{limits}\";",
      "the balance of the user is #{user.wallet(&:balance)}",
      "at the wallet [#{user.item.id}](http://www.zold.io/ledger.html?wallet=#{user.item.id})"
    )
    raise WTS::UserError, "E218: With #{amount} you are going over our limits, #{consumed} were sold by ALL \
users of WTS, while our limits are #{limits} (daily/weekly/monthly), sorry about this :("
  end
  bitcoin = (amount.to_zld(8).to_f * WTS::Rate.new(settings.toggles)).round(8)
  usd = (bitcoin * price).round(2)
  boss = user(settings.config['zerocrat']['login'])
  rewards = user(settings.config['rewards']['login'])
  job(exclusive: true) do |jid, log|
    log.info("Sending #{WTS::Dollars.new(usd)} via UpWork to #{email}...")
    f = exfee
    ops(log: log).pull
    ops(rewards, log: log).pull
    ops(boss, log: log).pull
    txn = ops(log: log).pay(
      keygap,
      boss.item.id,
      amount * (1.0 - f),
      "ZLD exchange to #{usd} UpWork, rate is #{rate}, fee is #{f}, job ID is #{jid}"
    )
    ops(log: log).pay(
      keygap,
      rewards.item.id,
      amount * f,
      "Fee for exchange of #{usd} UpWork, rate is #{rate}, fee is #{f}"
    )
    ops(log: log).push
    upwork(log: log).pay(
      contract,
      (usd * (1.0 - f)).round(2),
      "Zerocracy development, TID #{user.item.id}:#{txn.id}"
    )
    settings.payouts.add(
      user.login, user.item.id, amount,
      "#{WTS::Dollars.new(usd)} sent to UpWork #{contract}, \
the price was #{WTS::Dollars.new(price)}/BTC, the fee was #{(f * 100).round(2)}%"
    )
    settings.telepost.spam(
      "😢 Out: **#{amount}** [exchanged](https://blog.zold.io/2018/12/09/btc-to-zld.html)",
      "to #{WTS::Dollars.new(usd)} UpWork contract `#{contract}`",
      "by #{title_md} from #{anon_ip}",
      "from the wallet [#{user.item.id}](http://www.zold.io/ledger.html?wallet=#{user.item.id})",
      "with the remaining balance of #{user.wallet(&:balance)};",
      "BTC price at the time of exchange was [#{WTS::Dollars.new(price)}](https://blockchain.info/ticker);",
      "zolds were deposited to [#{boss.item.id}](http://www.zold.io/ledger.html?wallet=#{boss.item.id})",
      "of [#{boss.login}](https://github.com/#{boss.login}),",
      "the balance is #{boss.wallet(&:balance)} (#{boss.wallet(&:txns).count}t);",
      "the exchange fee of #{amount * f}",
      "was deposited to [#{rewards.item.id}](http://www.zold.io/ledger.html?wallet=#{rewards.item.id})",
      "of [#{rewards.login}](https://github.com/#{rewards.login}),",
      "the balance is #{rewards.wallet(&:balance)} (#{rewards.wallet(&:txns).count}t);",
      job_link(jid)
    )
  end
  flash('/zld-to-upwork', "We took #{amount} from your wallet and sent you #{WTS::Dollars.new(usd)} via UpWork")
end
