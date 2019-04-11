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
require 'sibit'
require 'zold/http'
require 'zold/json_page'
require_relative 'wts'
require_relative 'user_error'

#
# BTC gateway.
#
class WTS::Btc
  def initialize(log: Zold::Log::NULL)
    @log = log
    @sibit = Sibit.new(log: @log)
  end

  def price
    @sibit.price
  end

  # Get the latest block from the blockchain, scan all transactions visible
  # there and find those, which we are waiting for. Then, yield them one
  # by one if they haven't been seen yet in UTXOs.
  def monitor(assets, utxos, seen, max: 1)
    ours = Set.new(assets.all.map { |a| a[:address] })
    block = @sibit.latest
    count = 0
    while block != seen && count < max
      json = @sibit.get_json("/rawblock/#{block}")
      json['tx'].each do |t|
        t['out'].each do |o|
          next if o['spent']
          address = o['addr']
          next if address.nil?
          next unless ours.include?(address)
          hash = "#{t['hash']}:#{o['n']}"
          next if utxos.seen?(hash)
          assets.set(address, @sibit.balance(address))
          satoshi = o['value']
          yield(address, hash, satoshi)
          @log.info("Tx found at #{hash} for #{satoshi}s sent to #{address}")
        end
      end
      block = json['prev_block']
      count += 1
    end
  end

  # Send Bitcoins to the address
  def send(assets, _address, satoshi)
    batch = assets.prepare(satoshi)
    # send it to the network...
    assets.spent(batch)
  end
end
