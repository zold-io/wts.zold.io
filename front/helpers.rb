# SPDX-FileCopyrightText: Copyright (c) 2018-2025 Zerocracy
# SPDX-License-Identifier: MIT

require 'cgi'

helpers do
  def largetext(text)
    span = "<span style='display:inline-block;'>"
    span + CGI.escapeHTML(text)
      .tr("\n", '↵')
      .split(/(.{4})/)
      .map { |i| i.gsub(' ', "<span class='lightgray'>&#x2423;</span>") }
      .join('</span>' + span)
      .chars.map { |c| c.ord > 0x7f ? "<span class='firebrick'>\\x#{format('%x', c.ord)}</span>" : c }.join + '</span>'
  end
end
