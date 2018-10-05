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

#
# The stats.
#
class Stats
  # Max length of the line
  MAX = 512

  def initialize
    @history = {}
    @mutex = Mutex.new
  end

  def to_json
    @history.map do |m, h|
      sum = h.inject(&:+)
      [
        m,
        {
          'total': h.count,
          'sum': sum,
          'avg': (h.empty? ? 0 : (sum / h.count)),
          'max': h.max,
          'min': h.min
        }
      ]
    end.to_h
  end

  def put(metric, value)
    raise "Invalid type of \"#{value}\" (#{value.class.name})" unless value.is_a?(Integer) || value.is_a?(Float)
    @mutex.synchronize do
      @history[metric] = [] unless @history[metric]
      @history[metric] << value
      @history[metric].shift while @history[metric].count > Stats::MAX
    end
  end
end
