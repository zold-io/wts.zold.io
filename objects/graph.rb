# Copyright (c) 2018-2022 Zold
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

require 'zold/log'
require 'SVG/Graph/Line'
require_relative 'wts'
require_relative 'user_error'

#
# Graph in SVG.
#
# See: https://github.com/lumean/svg-graph2/blob/master/lib/SVG/Graph/Graph.rb
#
class WTS::Graph
  # How many total X-steps on the graph
  STEPS = 12
  private_constant :STEPS

  def initialize(ticks, log: Zold::Log::NULL)
    @ticks = ticks
    @log = log
  end

  def svg(keys, div, digits, title: '')
    sets = {}
    min = Time.now
    max = Time.now + STEPS * 24 * 60 * 60
    keys.each do |k|
      @ticks.fetch(k).each do |t|
        sets[k] = [] if sets[k].nil?
        sets[k] << { x: t[:created], y: t[:value] / div }
        min = t[:created] if min > t[:created]
        max = t[:created] if max < t[:created]
      end
    end
    raise WTS::UserError, 'E221: There are no ticks, sorry' if sets.empty?
    step = (max - min) / STEPS
    raise WTS::UserError, 'E222: Step is too small, can\'t render, sorry' if step.zero?
    params = {
      width: 400, height: 200,
      show_x_guidelines: true, show_y_guidelines: true,
      show_x_labels: true, show_y_labels: false,
      x_label_font_size: 10,
      key: keys.count > 1,
      step_include_first_x_label: false,
      stagger_x_labels: true,
      number_format: "%.#{digits}f",
      fields: (0..STEPS - 1).map { |i| (min + i * step).strftime('%m/%d') }
    }
    unless title.empty?
      params[:y_title] = title.gsub(/[^a-zA-Z0-9 ]/, ' ')
      params[:show_y_title] = true
    end
    g = SVG::Graph::Line.new(params)
    sets.each do |k, v|
      data = Array.new(STEPS, nil)
      v.group_by { |p| ((p[:x] - min) / step).to_i }.each do |s, points|
        data[s] = points.empty? ? 0 : points.map { |p| p[:y] }.max
      end
      g.add_data(title: k, data: data)
    end
    g.burn
  end
end
