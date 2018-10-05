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
  def initialize(age: 24 * 60 * 60)
    @age = age
    @history = {}
    @mutex = Mutex.new
  end

  def to_json
    @history.map do |m, h|
      data = h.map { |a| a[:value] }
      sum = data.inject(&:+)
      [
        m,
        {
          'total': data.count,
          'sum': sum,
          'avg': (data.empty? ? 0 : (sum / data.count)),
          'max': data.max,
          'min': data.min,
          'age': h.map { |a| a[:time] }.max - h.map { |a| a[:time] }.min
        }
      ]
    end.to_h
  end

  def put(metric, value)
    raise "Invalid type of \"#{value}\" (#{value.class.name})" unless value.is_a?(Integer) || value.is_a?(Float)
    @mutex.synchronize do
      @history[metric] = [] unless @history[metric]
      @history[metric] << { time: Time.now, value: value }
      @history[metric].reject! { |a| a[:time] < Time.now - @age }
    end
  end
end
