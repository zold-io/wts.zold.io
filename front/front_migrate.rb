# Copyright (c) 2018-2020 Zerocracy, Inc.
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
