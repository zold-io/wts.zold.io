/**
 * SPDX-FileCopyrightText: Copyright (c) 2018-2025 Zerocracy
 * SPDX-License-Identifier: MIT
 */

/*global $, window */

function wts_rerate(rate, price, fee) {
  'use strict';
  var txt = $('#zld').val();
  var zld = parseFloat(txt);
  if (zld === NaN) {
    $('#out').text('');
  } else {
    var btc = zld * rate * (1 - fee);
    var usd = btc * price;
    $('#out').text(
      'We will send exactly $' + usd.toFixed(0) +
      ', you will pay UpWork fees.'
    );
  }
}
