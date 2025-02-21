# SPDX-FileCopyrightText: Copyright (c) 2018-2025 Zerocracy
# SPDX-License-Identifier: MIT

require 'minitest/autorun'
require 'openssl'
require 'webmock/minitest'
require 'zold/http'
require 'zold/id'
require 'zold/key'
require_relative '../objects/item'
require_relative 'test__helper'

class WTS::ItemTest < Minitest::Test
  def test_create_and_read
    WebMock.allow_net_connect!
    item = WTS::Item.new("jeff13#{rand(999)}", t_pgsql, log: t_log)
    assert(!item.exists?)
    pvt = OpenSSL::PKey::RSA.new(2048)
    id = Zold::Id.new
    item.create(id, Zold::Key.new(text: pvt.to_pem))
    assert(item.exists?)
    assert_equal(id, item.id)
  end

  def test_attach_tags
    WebMock.allow_net_connect!
    item = WTS::Item.new("jeff32#{rand(999)}", t_pgsql, log: t_log)
    item.create(Zold::Id.new, Zold::Key.new(text: OpenSSL::PKey::RSA.new(2048).to_pem))
    tag = 'hey-you'
    assert(!item.tags.exists?(tag))
    item.tags.attach(tag)
    assert(item.tags.exists?(tag))
  end

  def test_wipes_keygap
    WebMock.allow_net_connect!
    item = WTS::Item.new("jeff095#{rand(999)}", t_pgsql, log: t_log)
    pvt = OpenSSL::PKey::RSA.new(2048)
    id = Zold::Id.new
    pem = pvt.to_pem
    key = Zold::Key.new(text: pem)
    keygap = item.create(id, key)
    assert_equal(key, item.key(keygap))
    assert_equal(id, item.id)
    assert(!item.wiped?)
    item.wipe(keygap)
    assert(item.wiped?)
    assert_equal(key, item.key(keygap))
  end

  def test_rename_change_login
    WebMock.allow_net_connect!
    before = "jeff#{rand(999)}"
    item = WTS::Item.new(before, t_pgsql, log: t_log)
    item.create(Zold::Id.new, Zold::Key.new(text: OpenSSL::PKey::RSA.new(2048).to_pem))
    item.tags.attach('some-tag')
    after = "peter#{rand(999)}"
    item.rename(after)
    assert_equal(after, item.login)
    assert(item.exists?)
  end
end
