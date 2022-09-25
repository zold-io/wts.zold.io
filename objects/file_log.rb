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

#
# File log.
#
class WTS::FileLog
  def initialize(file)
    @file = file
    FileUtils.mkdir_p(File.dirname(@file))
  end

  def content
    if File.exist?(@file)
      File.read(@file)
    else
      'There is no log as of yet...'
    end
  end

  def debug(msg)
    # nothing
  end

  def debug?
    false
  end

  def info(msg)
    print(msg)
  end

  def info?
    true
  end

  def error(msg)
    print("ERROR: #{msg}")
  end

  private

  def print(msg)
    File.open(@file, 'a') { |f| f.puts(msg) }
  end
end
