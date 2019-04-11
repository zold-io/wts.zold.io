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

require_relative 'pgsql'
require_relative 'user_error'

# Referrals.
# Author:: Yegor Bugayenko (yegor256@gmail.com)
# Copyright:: Copyright (c) 2018 Yegor Bugayenko
# License:: MIT
class WTS::Referrals
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
    row = @pgsql.exec('SELECT ref FROM referral WHERE login = $1 LIMIT 1', [login])
    raise WTS::UserError, "184: No referral for #{login}" if row.empty?
    row[0]['ref']
  end
end
