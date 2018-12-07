# Copyright (c) 2018 Yegor Bugayenko
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

require 'yaml'
require 'telebot'

# Telegram Bot.
# Author:: Yegor Bugayenko (yegor256@gmail.com)
# Copyright:: Copyright (c) 2018 Yegor Bugayenko
# License:: MIT
class Tbot
  # Fake one
  class Fake
    attr_reader :sent
    def initialize
      @sent = []
    end

    def post(msg)
      @sent << msg
    end
  end

  def initialize(token, chat)
    @token = token
    @client = Telebot::Client.new(token)
    @chat = chat
  end

  def start
    Telebot::Bot.new(@token).run do |_, message|
      post(
        "Here is your chat ID: #{message.chat.id}",
        message.chat.id
      )
    end
  end

  def post(msg, chat = @chat)
    @client.send_message(
      chat_id: chat,
      parse_mode: 'Markdown',
      disable_web_page_preview: true,
      text: msg
    )
  rescue Telebot::Error => e
    raise "#{e.message}: \"#{msg}\""
  end
end
