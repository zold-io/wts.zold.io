/**
 * SPDX-FileCopyrightText: Copyright (c) 2018-2025 Zerocracy
 * SPDX-License-Identifier: MIT
 */

/*global $, window */

function wts_recalc(rate, price) {
  'use strict';
  var txt = $('#zld').val();
  var zld = parseFloat(txt);
  if (isNaN(zld)) {
    $('#out').text('');
  } else {
    var btc = zld * rate;
    var usd = btc * price;
    $('#out').text('Approximately $' + usd.toFixed(2));
  }
}
