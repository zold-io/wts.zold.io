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

require 'SVG/Graph/Line'
require_relative 'user_error'

#
# Graph in SVG.
#
# See: https://github.com/lumean/svg-graph2/blob/master/lib/SVG/Graph/Graph.rb
#
class Graph
  def initialize(ticks)
    @ticks = ticks
  end

  def svg(keys, div)
    sets = {}
    min = max = Time.now.to_f
    @ticks.fetch.each do |t|
      t.each do |k, v|
        next unless keys.include?(k)
        sets[k] = [] if sets[k].nil?
        sets[k] << v / div
      end
      min = t['time'] if min > t['time']
      max = t['time'] if max < t['time']
    end
    raise UserError, 'There are no ticks, sorry' if sets.empty?
    g = SVG::Graph::Line.new(
      width: 400, height: 300,
      show_x_guidelines: true, show_y_guidelines: true,
      show_x_labels: true, show_y_labels: false,
      number_format: '%.0f',
      fields: (0..5).map { |i| Time.at(min + i * (max - min) / 6).strftime('%m/%d') }
    )
    sets.each { |k, v| g.add_data(title: k, data: v) }
    g.burn
  end
end
