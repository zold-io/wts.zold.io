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

require_relative 'user_error'

# Referrals.
# Author:: Yegor Bugayenko (yegor256@gmail.com)
# Copyright:: Copyright (c) 2018 Yegor Bugayenko
# License:: MIT
class WTS::Referrals
  class Crypt
    ALPHABET = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-'
    ENCODINGS = [
      # Generated with ALPHABET.split('').shuffle.join
      'MOhqm0PnycUZeLdK8Yv\-DCgNfb7FJtiHT52BrxoAkas9RWlXpEujSGI64VzQ31w',
      'xJCVNc0nRd7sDozhlw5aMW2q4A1SKr\-6FG8jk9YUyILEbvQHZ3tuTBOpmgXiePf',
      'HWk3BKjXzTbr5YD87GqpiwUISfvlLZg2uV6nQ4R9aNOy0txe1EF\-hPomCJcdMAs',
      'E3WG1vDUkB78smKYIR4fjybxiArt5C6wNoPhn2Qup\-JzeZqgcF0SHTalVd9LOXM',
      'TBRVtqDQ938OvPexSCnrgl52NM1KILAs6zfFYuy4dGhZmEaW7p0\-bUiXkojcHwJ',
      'urX\-vD3HiFt9SBxaTe7ONWhYzyJbmP4nUkAsEKgVfGwd6jc2lp5ZMLqRQ01oI8C',
      'k9MarwhgQCER3BZ1evOzpfcI2UPi\-0WFnbDtJmXdoTy57lsLYSKGjH6xu8q4NVA',
      'lQNacTqdr3m0iuVLtwRv7xIkJ1eKFCPjYXApMHs64WSh5BfgbE8OGnozUZ\-2yD9',
      'R7focy9gYDXGmwLSuJOZzrtibpTFU1MPvnVQEAsqH8h23C0\-N54eKIdakxWj6lB',
      'CdtM4gfFqGJRl2knxo7UsaZp\-95H3wi0hyADLQWujEvOKBIVSrP1YNXcbz8Tem6',
      'PldNJbzKFAETGDLXx1eR3UHc2ug85hnYIMjWqSOa0rZ4o6viCVytm9pwB7k\-fQs',
      'Na5GVYUHv6wFmth8cePDQk37bXTpASLuIKCs\-yj9Bd2ZfRrinE1q0OgxJzloW4M',
      'JPuOncwY63EXbo9NyDQxVqWhr8sdF24gHTtUpl\-LzZM5iGe7RvAB1ajmCSI0fKk',
      'iKnhSka5C3H\-gr0QJ69LPfd2x4DtMEqBO7IbZoGwAm1yNlVRYTXcjWszFvpeu8U',
      '6KkPx4waRo9tAjQq5WHuEgNDMzcmyb1nGd\-2VFXLTBpI38YiOJrf0UhvZ7sSleC',
      'MTceKFPkU9QthIzpv4mdOfuljgWoi3wbN1xV5As8Cy2aHnDGLBX0S\-6qJYE7rZR',
      '8zVu1rqO0TKj\-m5g6LWvcRHDFbBXxp7SdneAiIyZN9EUto2QlkfY34GshCMJwPa',
      'KD\-qzdFVwaWLl6tBNxUY5eXbi9TQc2kvf3yR1S8mHA04PpnOg7MJhrGEZsojuIC'
    ]

    def encode(text)
      pos = rand(ENCODINGS.count)
      "#{format('%02d', pos)}#{text.tr(ALPHABET, ENCODINGS[pos])}"
    end

    def decode(text)
      pos = text[0..1].to_i
      text[2..-1].tr(ENCODINGS[pos], ALPHABET)
    end
  end

  def initialize(pgsql, log: Zold::Log::NULL)
    @pgsql = pgsql
    @log = log
  end

  # Fetch them all, who were referred by me.
  def fetch(login)
    @pgsql.exec('SELECT * FROM referral WHERE ref = $1', [login]).map do |r|
      {
        login: r['login'],
        created: Time.parse(r['created']),
        utm_source: r['utm_source'],
        utm_medium: r['utm_medium'],
        utm_campaign: r['utm_campaign']
      }
    end
  end

  # Register it, if doesn't exist yet.
  def register(login, ref, source: '', medium: '', campaign: '')
    @pgsql.exec(
      [
        'INSERT INTO referral (login, ref, utm_source, utm_medium, utm_campaign)',
        'VALUES ($1, $2, $3, $4, $5)',
        'ON CONFLICT (login, ref) DO NOTHING'
      ].join(' '),
      [login, ref, source || '', medium || '', campaign || '']
    )
    @log.info("New referral registered at #{login} by #{ref}")
  end

  # Was this guy referred to us by someone and this ref is not expired?
  def exists?(login)
    !@pgsql.exec(
      'SELECT ref FROM referral WHERE login = $1 AND created > NOW() - INTERVAL \'32 DAYS\'',
      [login]
    ).empty?
  end

  # Get referral.
  def ref(login)
    row = @pgsql.exec(
      'SELECT ref FROM referral WHERE login = $1 OR login = $2 LIMIT 1',
      [login, Crypt.new.decode(login)]
    )
    raise WTS::UserError, "E184: No referral for #{login}" if row.empty?
    row[0]['ref']
  end
end
