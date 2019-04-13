# Copyright (c) 2018-2019 Zerocracy, Inc.
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

get '/pay' do
  features('pay')
  haml :pay, layout: :layout, locals: merged(
    page_title: title('pay')
  )
end

post '/do-pay' do
  features('pay')
  raise WTS::UserError, 'E109: Parameter "bnf" is not provided' if params[:bnf].nil?
  bnf = params[:bnf].strip
  raise WTS::UserError, 'E110: Parameter "amount" is not provided' if params[:amount].nil?
  amount = Zold::Amount.new(zld: params[:amount].to_f)
  if user.wallet_exists?
    balance = user.wallet(&:balance)
    raise WTS::UserError, "E197: Not enough funds to send #{amount} only #{balance} left" if balance < amount
  end
  raise WTS::UserError, 'E111: Parameter "details" is not provided' if params[:details].nil?
  details = params[:details]
  raise WTS::UserError, "E118: Invalid details \"#{details}\"" unless details =~ %r{^[a-zA-Z0-9\ @!?*_\-.:,'/]+$}
  if /^[a-f0-9]{16}$/.match?(bnf)
    bnf = Zold::Id.new(bnf)
    raise WTS::UserError, 'E112: You can\'t pay yourself' if bnf == user.item.id
  elsif /^[a-zA-Z0-9]+@[a-f0-9]{16}$/.match?(bnf)
    bnf = params[:bnf]
    raise WTS::UserError, 'E113: You can\'t pay yourself' if bnf.split('@')[1] == user.item.id.to_s
  elsif /^\\+[0-9]+$/.match?(bnf)
    friend = user(bnf[0..32].to_i.to_s)
    raise WTS::UserError, 'E114: The user with this mobile phone is not registered yet' unless friend.item.exists?
    bnf = friend.item.id
  elsif /^@[a-zA-Z0-9\-]+$/.match?(bnf)
    login = bnf.downcase.gsub(/^@/, '')
    raise WTS::UserError, "E115: Invalid GitHub user name: #{bnf.inspect}" unless login =~ /^[a-z0-9-]{3,32}$/
    raise WTS::UserError, 'E116: You can\'t pay yourself' if login == user.login
    raise WTS::UserError, "E189: GitHub user #{login.inspect} doesn't exist" unless github_exists?(login)
    friend = user(login)
    unless friend.item.exists?
      friend.create(settings.remotes)
      ops(friend).push
    end
    bnf = friend.item.id
  else
    raise WTS::UserError, "E190: Can't understand the beneficiary #{bnf.inspect}"
  end
  if settings.toggles.get('ban:do-pay').split(',').include?(confirmed_user.login)
    settings.telepost.spam(
      "The user #{title_md} from #{anon_ip} is trying to send #{amount} out,",
      'while their account is banned via "ban:do-pay";',
      "the balance of the user is #{user.wallet(&:balance)}",
      "at the wallet [#{user.item.id}](http://www.zold.io/ledger.html?wallet=#{user.item.id})"
    )
    raise WTS::UserError, 'E117: Your account is not allowed to send any payments at the moment, sorry'
  end
  headers['X-Zold-Job'] = job do |jid, log|
    log.info("Sending #{amount} to #{bnf}...")
    ops(log: log).pull
    raise WTS::UserError, "E119: You don't have enough funds to send #{amount}" if user.wallet(&:balance) < amount
    txn = ops(log: log).pay(keygap, bnf, amount, details)
    settings.jobs.result(jid, 'txn', txn.id.to_s)
    settings.jobs.result(jid, 'tid', "#{user.item.id}:#{txn.id}")
    ops(log: log).push
    settings.telepost.spam(
      "Payment sent by #{title_md}",
      "from [#{user.item.id}](http://www.zold.io/ledger.html?wallet=#{user.item.id})",
      "with the remaining balance of #{user.wallet(&:balance)}",
      "to `#{txn.prefix}` at [#{txn.bnf}](http://www.zold.io/ledger.html?wallet=#{txn.bnf})",
      "for **#{txn.amount}** from #{anon_ip}:",
      "\"#{safe_md(details)}\";",
      job_link(jid)
    )
    callback(
      tid: "#{user.item.id}:#{txn.id}",
      login: user.login,
      prefix: txn.prefix,
      source: txn.bnf.to_s,
      amount: txn.amount.to_i,
      details: txn.details
    )
  end
  flash('/', "Payment has been sent to #{bnf} for #{amount}")
end
