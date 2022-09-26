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
