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

require 'backtrace'
require 'bitcoin'
require 'zold/http'
require 'zold/json_page'
require_relative 'wts'
require_relative 'user_error'

#
# BTC gateway.
#
class WTS::Btc
  # Fake
  class Fake
    def price
      4000
    end

    def monitor(_)
      # nothing
    end

    def create
      { hash: '1yrhsahfdjdfkjslk', pvt: '', pub: '' }
    end
  end

  def initialize(log: Zold::Log::NULL)
    @log = log
  end

  # Current price of one BTC, in US dollars
  def price
    JSON.parse(Zold::Http.new(uri: 'https://blockchain.info/ticker').get.body)['USD']['15m']
  end

  # Create new BTC address to accept payments, and returns {hash, pvt}
  def create
    pvt, pub = Bitcoin.generate_key
    address = Bitcoin.pubkey_to_address(pub)
    @log.info("New Bitcoin address created: #{address}")
    { hash: address, pvt: pvt, pub: pub }
  end

  def monitor(addresses)
    height = Zold::Http.new(uri: 'https://blockchain.info/q/getblockcount/').get.body.to_i
    raise 'Something is wrong with Blockchain API' if height.zero?
    addresses.all.each do |a|
      res = Zold::Http.new(uri: "https://blockchain.info/rawaddr/#{a[:hash]}").get
      next if res.code != 200
      Zold::JsonPage.new(res.body).to_hash['txs'].each do |t|
        confirmations = height - (t['block_height'] || height)
        satoshi = t['inputs'][0]['prev_out']['value']
        txhash = t['hash']
        yield a[:hash], txhash, satoshi, confirmations
        @log.info("Tx found at #{txhash} for #{satoshi}sat with #{confirmations}cnf sent to #{a[:hash]}")
      end
    end
  end

  # Send Bitcoins to the address
  def send(assets, _address, satoshi)
    batch = assets.prepare(satoshi)
    # send it to the network...
    assets.spent(batch)
  end

  # Returns TRUE if transaction with this amount and confirmations is trustable
  def trustable?(amount, confirmations)
    return false if confirmations.zero?
    return false if confirmations < 2 && amount > 100_000 # 0.001 BTC
    return false if confirmations < 3 && amount > 1_000_000 # 0.01 BTC
    return false if confirmations < 4 && amount > 10_000_000 # 0.1 BTC
    return false if confirmations < 5 && amount > 100_000_000 # 1 BTC
    true
  end
end
