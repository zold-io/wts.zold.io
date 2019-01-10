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

  def svg(keys, div, digits)
    sets = {}
    min = max = Time.now.to_f
    @ticks.fetch.each do |t|
      time = t['time']
      t.each do |k, v|
        next unless keys.include?(k)
        sets[k] = [] if sets[k].nil?
        sets[k] << { x: time, y: v / div }
      end
      min = time if min > time
      max = time if max < time
    end
    raise UserError, 'There are no ticks, sorry' if sets.empty?
    steps = 12
    step = (max - min) / steps
    raise UserError, 'Step is zero, sorry' if step.zero?
    g = SVG::Graph::Line.new(
      width: 400, height: 200,
      show_x_guidelines: true, show_y_guidelines: true,
      show_x_labels: true, show_y_labels: false,
      number_format: "%.#{digits}f",
      fields: (0..steps - 1).map { |i| Time.at((min + i * step) / 1000).strftime('%m/%d') }
    )
    sets.each do |k, v|
      g.add_data(
        title: k,
        data: v.group_by { |p| ((p[:x] - min) / step).to_i }
          .values
          .map { |vals| vals.empty? ? 0 : vals.map { |p| p[:y] }.inject(&:+) / v.size }
      )
    end
    g.burn
  end
end
