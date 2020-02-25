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

require 'securerandom'
require_relative '../objects/receipts'

set :receipts, WTS::Receipts.new(settings.pgsql, log: settings.log)

get '/receipt' do
  id = params[:txn].to_i
  txn = user.wallet(&:txns).find { |t| t.id == id && (t.amount.negative? || user.fake?) }
  raise WTS::UserError, "E223: There is no transaction ##{id} in your wallet" if txn.nil?
  haml :receipt, layout: :layout, locals: merged(
    page_title: title('receipt'),
    wallet: user.item.id,
    txn: txn.id,
    zld: txn.amount * -1,
    usd: WTS::Rate.new(settings.toggles).to_f * price * txn.amount.to_f * -1
  )
end

post '/do-receipt' do
  details = [
    "Date: #{Time.now.utc.iso8601}",
    "Wallet ID: #{user.item.id}",
    "Transaction ID: #{params[:txn]}",
    "Amount: #{params[:usd]} USD",
    "ZLD: #{params[:zld]}",
    '',
    "Paid by: #{params[:payer]}",
    "Paid to: #{params[:recipient]}",
    '',
    "Payment details: #{params[:details]}"
  ].join("\n")
  hash = (params[:hash] || SecureRandom.hex).gsub(/[^a-f0-9A-F]/, '')[0..8].upcase
  id = settings.receipts.create(user.login, hash, details)
  flash("/rcpt/#{hash}", "The receipt ##{id} has been generated with #{hash.inspect} hash")
end

get '/rcpt/{hash}' do
  hash = params[:hash]
  details = settings.receipts.details(hash)
  haml :rcpt, layout: :layout, locals: merged(
    page_title: hash,
    hash: hash,
    details: details
  )
end
