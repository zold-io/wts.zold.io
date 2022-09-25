# Copyright (c) 2018-2022 Zold
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
    page_title: title('pay'),
    rate: WTS::Rate.new(settings.toggles).to_f,
    price: price
  )
end

# Send a payment from the wallet to someone else. These POST arguments are expected:
#  bnf: Beneficiary, either wallet ID or GitHub login or phone number
#  details: The text to add to the transaction
#  amount: In ZLD
#  keygap: The keygap
post '/do-pay' do
  features('pay')
  raise WTS::UserError, 'E109: Parameter "bnf" is not provided' if params[:bnf].nil?
  bnf = params[:bnf].strip
  amount = parsed_amount
  if user.wallet_exists?
    balance = user.wallet(&:balance)
    debt = user.wallet { |w| Zold::Tax.new(w).debt }
    if balance - debt < amount
      raise WTS::UserError, "E197: Not enough funds to send #{amount.to_zld} \
only #{balance.to_zld} left (the debt is #{debt.to_zld})"
    end
  end
  raise WTS::UserError, 'E111: Parameter "details" is not provided' if params[:details].nil?
  details = params[:details]
  unless %r{^[a-zA-Z0-9\ @!?*_\-.:,'/]+$}.match?(details)
    raise WTS::UserError, "E118: Invalid details #{details.inspect}, \
see the White Paper, only a limited subset of characters is allowed: [a-zA-Z0-9@!?*_-,:,'/]"
  end
  if /^[a-f0-9]{16}$/.match?(bnf)
    bnf = Zold::Id.new(bnf)
    raise WTS::UserError, 'E112: You can\'t pay yourself' if bnf == user.item.id
  elsif /^[a-zA-Z0-9]+@[a-f0-9]{16}$/.match?(bnf)
    raise WTS::UserError, 'E113: You can\'t pay yourself' if bnf.split('@')[1] == user.item.id.to_s
  elsif /^\\+[0-9]+$/.match?(bnf)
    friend = user(bnf[0..32].to_i.to_s)
    raise WTS::UserError, 'E114: The user with this mobile phone is not registered yet' unless friend.item.exists?
    bnf = friend.item.id
  elsif /^@[a-zA-Z0-9\-]+$/.match?(bnf)
    login = bnf.downcase.gsub(/^@/, '')
    raise WTS::UserError, "E115: Invalid GitHub user name: #{bnf.inspect}" unless login =~ /^[a-z0-9-]{3,32}$/
    raise WTS::UserError, 'E116: You can\'t pay yourself' if login == user.login
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
  user.item.key(keygap) unless user.fake? # To check the validity of the keygap
  headers['X-Zold-Job'] = job do |jid, log|
    log.info("Sending #{amount} to #{bnf}...")
    ops(log: log).pull
    raise WTS::UserError, "E119: You don't have enough funds to send #{amount}" if user.wallet(&:balance) < amount
    txn = ops(log: log).pay(keygap, bnf, amount, details)
    settings.jobs.result(jid, 'txn', txn.id.to_s)
    settings.jobs.result(jid, 'tid', "#{user.item.id}:#{txn.id}")
    ops(log: log).push
    if (txn.amount * -1) > Zold::Amount.new(zld: 16.0)
      settings.telepost.spam(
        "🤝 #{txn.amount * -1}: A new payment sent by #{title_md}",
        "from [#{user.item.id}](http://www.zold.io/ledger.html?wallet=#{user.item.id})",
        "with the remaining balance of #{user.wallet(&:balance)} (#{user.wallet(&:txns).count}t)",
        "to `#{txn.prefix}` at [#{txn.bnf}](http://www.zold.io/ledger.html?wallet=#{txn.bnf})",
        "for **#{txn.amount * -1}** from #{anon_ip}:",
        "\"#{safe_md(details)}\";",
        job_link(jid)
      )
    end
  end
  flash('/', "Payment has been sent to #{bnf} for #{amount.to_zld}")
end

def parsed_amount
  raise WTS::UserError, 'E110: Parameter "amount" is not provided' if params[:amount].nil?
  param = params[:amount]
  amount = if /^[0-9]+z$/.match?(param)
    Zold::Amount.new(zents: param.to_i)
  elsif /^[0-9]+(\.[0-9]+)?$/.match?(param)
    Zold::Amount.new(zld: param.to_f)
  else
    raise WTS::UserError, 'E201: The amount must be only digits or must end with "z"'
  end
  raise WTS::UserError, 'E203: The amount can\'t be zero' if amount.zero?
  raise WTS::UserError, 'E204: The amount can\'t be negative' if amount.negative?
  amount
end
