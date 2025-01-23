/**
 * Copyright (c) 2018-2025 Zerocracy
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the 'Software'), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED 'AS IS', WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

/*global $, window */

function wts_info(text) {
  'use strict';
  $('#error').removeClass('firebrick').text('INFO: ' + text);
  $('#button').removeAttr('disabled');
}

function wts_error(xhr) {
  'use strict';
  var msg;
  if (typeof xhr === 'string') {
    msg = xhr;
  } else {
    msg = xhr.getResponseHeader('X-Zold-Error');
  }
  $('#error').addClass('firebrick').html(
    'ERROR: <strong>' + msg + '</strong>. If the description of the ' +
    'error doesn\'t help, most likely this ' +
    'is our internal problem. Try to reload this page and start from scratch. ' +
    'If this doesn\'t help, please submit a ticket to our '+
    '<a href="https://github.com/zold-io/wts.zold.io">GitHub repository</a> or ' +
    'seek help in our <a href="https://t.me/zold_io">Telegram group</a>.'
  );
  $('#button').attr('disabled', true);
}

function wts_recalc() {
  'use strict';
  wts_info('Loading rates...')
  $.ajax({
    dataType: 'json',
    url: '/rate.json?noredirect=1',
    success: function(json) {
      var rate = json.usd_rate;
      var btc = parseFloat($('#btc').val());
      if (btc > 999) {
        wts_error('That\'s too much');
        return;
      }
      var months = parseFloat($('#months').val());
      if (months > 60) {
        wts_error('That\'s too long');
        return;
      }
      var zld = btc / json.effective_rate;
      $('#zld').text(Math.round(zld));
      var spend = zld * rate
      $('#spend').text('$' + spend.toFixed(2));
      var zc_input = spend * Math.pow(1.04, months) - spend;
      $('#zc_input').text('$' + zc_input.toFixed(2));
      var btc_growth = spend * Math.pow(1.1, months) - spend;
      $('#btc_growth').text('$' + btc_growth.toFixed(2));
      var gross = (spend + btc_growth + zc_input);
      $('#gross').text('$' + gross.toFixed(2));
      var fee = -1 * gross * 0.08;
      $('#fee').text('$' + fee.toFixed(2));
      var net = gross + fee - spend;
      $('#net').text('$' + net.toFixed(2));
      if (net > 0) {
        $('#net').removeClass('firebrick').addClass('seagreen');
      } else {
        $('#net').addClass('firebrick').removeClass('seagreen');
      }
      wts_info('The current rate of ' + json.effective_rate + 'BTC/ZLD and $' + json.usd_rate + '/ZLD loaded')
    },
    error: function(xhr) {
      wts_error(xhr);
      window.setTimeout(wts_recalc, 3000);
    }
  });
}

function wts_step5(token) {
  'use strict';
  $('#step4').hide();
  $('#amount').text($('#btc').text());
  wts_info('Requesting BTC address for user ' + token + '...');
  $.ajax({
    dataType: 'text',
    url: '/btc-to-zld?noredirect=1',
    headers: { 'X-Zold-Wts': token },
    success: function(data, textStatus, request) {
      var address = request.getResponseHeader('X-Zold-BtcAddress');
      $('#step5').show();
      $('#step6').hide();
      $('#address').text(address);
      $('#qr').attr('src', 'https://chart.googleapis.com/chart?chs=256x256&cht=qr&chl=bitcoin:' + address);
      wts_info('BTC address for user ' + token + ' acquired');
    },
    error: function(xhr) { wts_error(xhr); }
  });
}

function wts_step4(token) {
  'use strict';
  $.ajax({
    dataType: 'text',
    url: '/confirmed?noredirect=1',
    headers: { 'X-Zold-Wts': token },
    success: function(text) {
      if (text === 'yes') {
        wts_info('The keygap of ' + token + ' is already confirmed (existing account)');
        wts_step5(token);
      } else {
        wts_info('Confirming keygap of ' + token + '...');
        $.ajax({
          dataType: 'text',
          url: '/keygap?noredirect=1',
          headers: { 'X-Zold-Wts': token },
          success: function(text) {
            var keygap = text;
            $('#step4').show();
            $('#keygap').text(keygap);
            wts_info('Keygap of ' + token + ' retrieved and has to be confirmed...');
            $('#button').val('Confirm').off('click').on('click', function () {
              $.ajax({
                dataType: 'text',
                url: '/do-confirm?noredirect=1&keygap=' + keygap,
                headers: { 'X-Zold-Wts': token },
                success: function(text) {
                  wts_info('Keygap of ' + token + ' confirmed, account is ready');
                  wts_step5(token);
                },
                error: function(xhr) { wts_error(xhr); }
              });
            });
          },
          error: function(xhr) { wts_error(xhr); }
        });
      }
    }
  });
}

function wts_step3() {
  'use strict';
  var phone = $('#phone').text();
  var code = $('#code').val();
  wts_info('Confirming ' + phone + ' with ' + code + '...');
  $.ajax({
    dataType: 'text',
    url: '/mobile/token?noredirect=1&phone=' + phone + '&code=' + code,
    success: function(text) {
      $('#step3').hide();
      $('#step5').hide();
      $('#step4').show();
      wts_info('The auth code ' + code + ' was accepted for ' + phone);
      wts_step4(text);
    },
    error: function(xhr) { wts_error(xhr); }
  });
}

function wts_step2() {
  'use strict';
  var phone = $('#phone').val();
  wts_info('Sending SMS to phone ' + phone + '...');
  $.ajax({
    dataType: 'text',
    url: '/mobile/send?noredirect=1&phone=' + phone,
    success: function(text) {
      $('#step3').show();
      $('#phone').replaceWith('<strong id="phone">' + $('#phone').val() + '</strong>');
      $('#button').val('Confirm').off('click').on('click', wts_step3);
      $('#code').focus();
      wts_info('The SMS has been delivered to ' + phone);
    },
    error: function(xhr) { wts_error(xhr); }
  });
}

function wts_step1() {
  'use strict';
  $('#step2').show();
  $('#btc').replaceWith('<span id="btc">' + $('#btc').val() + '</span>');
  $('#months').replaceWith('<span id="months">' + $('#months').val() + '</span>');
  $('#button').val('Send').off('click').on('click', wts_step2);
  $('#phone').focus();
}

$(function() {
  'use strict';
  wts_recalc();
  $('#button').on('click', wts_step1);
});

