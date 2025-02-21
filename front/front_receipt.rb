# SPDX-FileCopyrightText: Copyright (c) 2018-2025 Zerocracy
# SPDX-License-Identifier: MIT

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
