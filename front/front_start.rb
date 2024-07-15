# Copyright (c) 2018-2024 Zerocracy
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

get '/create' do
  features('create')
  job do |jid, log|
    log.info('Creating a new wallet by /create request...')
    user.create(settings.remotes)
    ops(log: log).push
    settings.telepost.spam(
      "The user #{title_md}",
      "created a new wallet [#{user.item.id}](http://www.zold.io/ledger.html?wallet=#{user.item.id})",
      "from #{anon_ip};",
      job_link(jid)
    )
    if user.item.tags.exists?('sign-up-bonus')
      settings.log.debug("Won't send sign-up bonus to #{user.login}, it's already there")
    elsif known?
      boss = user(settings.config['rewards']['login'])
      amount = Zold::Amount.new(zld: 0.256)
      job(boss) do |jid2, log2|
        if boss.wallet(&:balance).zero?
          settings.telepost.spam(
            "A sign-up bonus of #{amount} can't be sent",
            "to #{title_md} from #{anon_ip}",
            "to their wallet [#{user.item.id}](http://www.zold.io/ledger.html?wallet=#{user.item.id})",
            "from our wallet [#{boss.item.id}](http://www.zold.io/ledger.html?wallet=#{boss.item.id})",
            "of [#{boss.login}](https://github.com/#{boss.login})",
            "because there is zero funds, only #{boss.wallet(&:balance)} left;",
            job_link(jid2)
          )
        else
          amount = [boss.wallet(&:balance).mul(0.5), amount].min
          ops(boss, log: log2).pull
          ops(boss, log: log2).pay(
            settings.config['rewards']['keygap'], user.item.id,
            amount, "WTS signup bonus to #{user.login}"
          )
          ops(boss, log: log2).push
          user.item.tags.attach('sign-up-bonus')
          settings.telepost.spam(
            "The sign-up bonus of #{amount} has been sent",
            "to #{title_md} from #{anon_ip},",
            "to their wallet [#{user.item.id}](http://www.zold.io/ledger.html?wallet=#{user.item.id})",
            "from our wallet [#{boss.item.id}](http://www.zold.io/ledger.html?wallet=#{boss.item.id})",
            "of [#{boss.login}](https://github.com/#{boss.login})",
            "with the remaining balance of #{boss.wallet(&:balance)} (#{boss.wallet(&:txns).count}t);",
            job_link(jid2)
          )
        end
      end
    elsif !user.mobile?
      settings.telepost.spam(
        "A sign-up bonus won't be sent to #{title_md} from #{anon_ip}",
        "with the wallet [#{user.item.id}](http://www.zold.io/ledger.html?wallet=#{user.item.id})",
        "because this user is not [known](https://www.0crat.com/known/#{user.login}) to Zerocracy;",
        job_link(jid)
      )
    end
  end
  flash('/', 'Your wallet is created and will be pushed soon')
end

get '/keygap' do
  if user.item.wiped?
    raise WTS::UserError, "E108: We don't have the keygap for wallet ##{user.item.id} in the database anymore"
  end
  content_type 'text/plain'
  user.item.keygap
end

get '/pull' do
  headers['X-Zold-Job'] = job do |_jid, log|
    if user.wallet_exists? && !params[:force]
      log.info("We won't pull the wallet #{user.item.id} since it already exists")
    else
      log.info("Pulling wallet #{user.item.id} via /pull...")
      ops(log: log).remove
      ops(log: log).pull
    end
  end
  flash('/', "Your wallet #{user.item.id} will be pulled soon")
end

get '/restart' do
  features('restart')
  haml :restart, layout: :layout, locals: merged(
    page_title: title('restart')
  )
end
