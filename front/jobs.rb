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

get '/job' do
  prohibit('api')
  id = params['id']
  raise WTS::UserError, "150: Job in 'id' query parameter is mandatory" if id.nil? || id.empty?
  raise WTS::UserError, "151: Job ID #{id} is not found" unless settings.jobs.exists?(id)
  content_type 'text/plain', charset: 'utf-8'
  settings.jobs.read(id)
end

get '/job.json' do
  prohibit('api')
  id = params['id']
  raise WTS::UserError, "152: Job in 'id' query parameter is mandatory" if id.nil? || id.empty?
  raise WTS::UserError, "153: Job ID #{id} is not found" unless settings.jobs.exists?(id)
  content_type 'application/json'
  JSON.pretty_generate(
    {
      id: id,
      status: settings.jobs.status(id),
      output_length: settings.jobs.output(id).length
    }.merge(settings.jobs.results(id))
  )
end

get '/output' do
  prohibit('api')
  id = params['id']
  raise WTS::UserError, "154: Job in 'id' query parameter is mandatory" if id.nil? || id.empty?
  raise WTS::UserError, "155: Job ID #{id} is not found" unless settings.jobs.exists?(id)
  content_type 'text/plain', charset: 'utf-8'
  headers['X-Zold-JobStatus'] = settings.jobs.status(id)
  settings.jobs.output(id)
end
