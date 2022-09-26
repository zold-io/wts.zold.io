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

settings.daemons.start('hosting-bonuses', 10 * 60) do
  login = settings.config['rewards']['login']
  boss = user(login)
  if boss.item.exists?
    job(boss) do |jid, log|
      pay_hosting_bonuses(boss, jid, log)
    end
  end
end

def pay_hosting_bonuses(boss, jid, log)
  bonus = Zold::Amount.new(zld: 1.0)
  ops(boss, log: log).remove
  ops(boss, log: log).pull
  latest = boss.wallet(&:txns).reverse.find { |t| t.amount.negative? }
  return if !latest.nil? && latest.date > Time.now - (60 * 60)
  if boss.wallet(&:balance) < bonus
    if !latest.nil? && latest.date > Time.now - (60 * 60)
      settings.telepost.spam(
        'The hosting bonuses paying wallet',
        "[#{boss.item.id}](http://www.zold.io/ledger.html?wallet=#{boss.item.id})",
        "is almost empty, the balance is just #{boss.wallet(&:balance)};",
        "we can\'t pay #{bonus} of bonuses now;",
        'we should wait until the next BTC/ZLD',
        '[exchange](https://blog.zold.io/2018/12/09/btc-to-zld.html) happens;',
        job_link(jid)
      )
    end
    return
  end
  require 'zold/commands/remote'
  cmd = Zold::Remote.new(remotes: settings.remotes, log: log)
  cmd.run(%w[remote update --depth=5])
  cmd.run(%w[remote show])
  winners = cmd.run(%w[remote elect --min-score=2 --max-winners=8 --ignore-masters])
  winners.each do |score|
    ops(boss, log: log).pull
    ops(boss, log: log).pay_taxes(settings.config['rewards']['keygap'])
    ops(boss, log: log).push
    ops(boss, log: log).pay(
      settings.config['rewards']['keygap'],
      score.invoice,
      bonus / winners.count,
      "Hosting bonus for #{score.host} #{score.port} #{score.value}"
    )
    ops(boss, log: log).push
  end
  if winners.empty?
    settings.telepost.spam(
      'Attention, no hosting [bonuses](https://blog.zold.io/2018/08/14/hosting-bonuses.html)',
      'were paid because no nodes were found,',
      "which would deserve that, among [#{settings.remotes.all.count} visible](https://wts.zold.io/remotes);",
      'something is wrong with the network,',
      'check this [health](http://www.zold.io/health.html) page;',
      job_link(jid)
    )
    return
  end
  settings.telepost.spam(
    '🍓 Hosting [bonus](https://blog.zold.io/2018/08/14/hosting-bonuses.html)',
    "of **#{bonus}** has been distributed among #{winners.count} wallets",
    '[visible](https://wts.zold.io/remotes) to us at the moment,',
    "among #{settings.remotes.all.count} [others](http://www.zold.io/health.html):",
    winners.map do |s|
      "[#{s.host}:#{s.port}](http://www.zold.io/ledger.html?wallet=#{s.invoice.split('@')[1]})/#{s.value}"
    end.join(', ') + ';',
    "the payer is #{title_md(boss)} with the wallet",
    "[#{boss.item.id}](http://www.zold.io/ledger.html?wallet=#{boss.item.id}),",
    "the remaining balance is #{boss.wallet(&:balance)} (#{boss.wallet(&:txns).count}t);",
    job_link(jid)
  )
  return if boss.wallet(&:txns).count < 1000
  before = boss.item.id
  ops(boss, log: log).migrate(settings.config['rewards']['keygap'])
  settings.telepost.spam(
    'The wallet with hosting [bonuses](https://blog.zold.io/2018/08/14/hosting-bonuses.html)',
    "has been migrated from [#{before}](http://www.zold.io/ledger.html?wallet=#{before})",
    "to a new place [#{boss.item.id}](http://www.zold.io/ledger.html?wallet=#{boss.item.id}),",
    "the balance is #{boss.wallet(&:balance)};",
    job_link(jid)
  )
end
