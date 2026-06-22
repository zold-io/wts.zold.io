# frozen_string_literal: true

# SPDX-FileCopyrightText: Copyright (c) 2018-2026 Zerocracy
# SPDX-License-Identifier: MIT

require 'loog'
require 'openssl'
require 'tempfile'
require 'zold/id'
require_relative 'user_error'
require_relative 'wts'

class WTS::User
  attr_reader :item, :login

  def initialize(login, item, wallets, log: Loog::NULL)
    @login = login.downcase
    @item = item
    @wallets = wallets
    @log = log
  end

  def fake?
    @login == Zold::Id::ROOT.to_s
  end

  def mobile?
    /^[0-9]+$/.match?(@login)
  end

  # rubocop:disable Naming/PredicateMethod
  def create(remotes = Zold::Remotes::Empty.new)
    rsa = OpenSSL::PKey::RSA.new(2048)
    wallet =
      Tempfile.open do |f|
        File.write(f, rsa.public_key.to_pem)
        require('zold/commands/create')
        Zold::Create.new(wallets: @wallets, remotes: remotes, log: @log).run(['create', "--public-key=#{f.path}"])
      end
    @item.create(wallet, Zold::Key.new(text: rsa.to_pem))
    @log.info("Wallet #{wallet} created successfully\n")
    true
  end
  # rubocop:enable Naming/PredicateMethod

  def invoice
    require('zold/commands/invoice')
    Zold::Invoice.new(wallets: @wallets, remotes: @remotes, copies: @copies, log: @log).run(
      ['invoice', wallet(&:id).to_s]
    )
  end

  def confirmed?
    @item.wiped?
  end

  def confirm(keygap)
    raise(RuntimeError, 'Keygap can\'t be nil') if keygap.nil?
    @item.wipe(keygap)
  end

  def keygap
    raise(RuntimeError, 'The user has already confirmed the keygap, we don\'t keep it anymore') if confirmed?
    @item.keygap
  end

  def wallet_exists?
    @item.exists? && @wallets.acq(@item.id, &:exists?)
  end

  def wallet
    id = @item.id
    @wallets.acq(id) do |wallet|
      raise(WTS::UserError, "E100: You have to pull the wallet #{id} first (#{@login})") unless wallet.exists?
      @item.touch
      yield(wallet)
    end
  end
end
