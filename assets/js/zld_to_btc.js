/**
 * SPDX-FileCopyrightText: Copyright (c) 2018-2025 Zerocracy
 * SPDX-License-Identifier: MIT
 */

/*global $, window */

function wts_rerate(rate, price, fee) {
  'use strict';
  var txt = $('#zld').val();
  var btc_fee = parseFloat($('#btc_fee').text());
  var zld = parseFloat(txt);
  if (isNaN(zld)) {
    $('#out').text('');
  } else {
    var btc = zld * rate * (1 - fee) - btc_fee;
    var usd = btc * price;
    $('#out').text(
      'You will receive approximately ' + btc.toFixed(5) +
      ' BTC, which is about $' + usd.toFixed(2)
    );
  }
}
