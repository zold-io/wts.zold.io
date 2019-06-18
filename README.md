<img src="https://www.zold.io/logo.svg" width="92px" height="92px"/>

[![Donate via Zerocracy](https://www.0crat.com/contrib-badge/CB28FH2NR.svg)](https://www.0crat.com/contrib/CB28FH2NR)

[![EO principles respected here](https://www.elegantobjects.org/badge.svg)](https://www.elegantobjects.org)
[![Managed by Zerocracy](https://www.0crat.com/badge/CAZPZR9FS.svg)](https://www.0crat.com/p/CAZPZR9FS)
[![DevOps By Rultor.com](http://www.rultor.com/b/zold-io/wts.zold.io)](http://www.rultor.com/p/zold-io/wts.zold.io)
[![We recommend RubyMine](https://www.elegantobjects.org/rubymine.svg)](https://www.jetbrains.com/ruby/)

[![Build Status](https://travis-ci.org/zold-io/wts.zold.io.svg)](https://travis-ci.org/zold-io/wts.zold.io)
[![PDD status](http://www.0pdd.com/svg?name=zold-io/wts.zold.io)](http://www.0pdd.com/p?name=zold-io/wts.zold.io)
[![Test Coverage](https://img.shields.io/codecov/c/github/zold-io/wts.zold.io.svg)](https://codecov.io/github/zold-io/wts.zold.io?branch=master)
[![Maintainability](https://api.codeclimate.com/v1/badges/25b798dc13147f13bb59/maintainability)](https://codeclimate.com/github/zold-io/wts.zold.io/maintainability)
[![Hits-of-Code](https://hitsofcode.com/github/zold-io/wts.zold.io)](https://hitsofcode.com/view/github/zold-io/wts.zold.io)

[![Availability at SixNines](https://www.sixnines.io/b/2e391)](https://www.sixnines.io/h/2e391)

Here is the [White Paper](https://papers.zold.io//wp.pdf).

Join our [Telegram group](https://t.me/zold_io) to discuss it all live.

The license is [MIT](https://github.com/zold-io/wts.zold.io/blob/master/LICENSE.txt).

Zold Web WalleTS (hence the _WTS_ name) is a simple web front to the Zold
network. In order to use all the features of Zold cryptocurrency, you will need
a command like client, which you can get [here](https://github.com/zold-io/zold).
However, most of us are too lazy to learn the command line interface, that's
why we created this web interface. Via WTS you can create a wallet, push
it to the network, pull it from there, and make payments to other users.
Aside from that, you can also use its RESTful API, Mobile API, Callback API,
and many other tools to monitor the network and to manage your wallet.

If you are a crypto-exchange, an online shop, or a developer of a mobile wallet,
you may find this blog post interesting: [How to Integrate](https://blog.zold.io/2019/03/11/how-to-integrate.html).
It explains how you can utilize WTS in order to manage zolds that belong
to your users/customers.

There is Ruby SDK for the WTS platform: [zold-io/zold-ruby-sdk](https://github.com/zold-io/zold-ruby-sdk).

## HTTP API

First, you should get your API token from the [API](https://wts.zold.io/api) tab of your account.
To create an account you just need to login with your mobile phone. There
is no special sign-up form or procedure. Once you login, your account _and_
your Zold wallet are created automatically.

Then, say, you want to send some zolds to `@yegor256`, your token is
`user-111222333444`, and your
[keygap](https://blog.zold.io/2018/07/18/keygap.html) is `84Hjsow9`.
You do the following POST HTTP request:

```
POST /do-pay?noredirect=1 HTTP/1.1
Content-Type: application/x-www-form-urlencoded
Host: wts.zold.io
X-Zold-Wts: user-111222333444
bnf=yegor256&amount=19.99&details=For+the+pizza&keygap=84Hjsow9
```

If you want to send zents, add `z` to the end of the amount, for example:
`8900000z`.

You can do the same from the command line, using
[curl](https://en.wikipedia.org/wiki/CURL):

```bash
curl https://wts.zold.io/do-pay?noredirect=1 \
  --request POST \
  --header "Content-Type: application/x-www-form-urlencoded" \
  --header "X-Zold-Wts: user-111222333444" \
  --data "bnf=yegor256" \
  --data "amount=19.99" \
  --data "details=For+the+pizza" \
  --data "keygap=84Hjsow9"
```

You will get `200` response if the payment processing has been started.
Pay attention, this response doesn't mean that the payment has been
successfully sent. The request processing is asynchronous!
The `X-Zold-Job` header of the response will
contain the ID of the job, which is executed on the server.
Later, you can check the status of the job via the `/job.json` entry point, using its ID.

If you get a non-200 response, check the `X-Zold-Error` response HTTP header,
it will explain the problem with a more or less human-readable error message.
The response body will contain a full Ruby stacktrace, which you may report
to us if it doesn't explain the problem completely. Don't hesitate to
[submit a ticket](https://github.com/zold-io/wts.zold.io/issues) when something goes wrong.

You can also send zolds to the wallet ID or the mobile phone. Just use
them instead of the GitHub user name in the `bnf` parameter.

There are more entry points. Here is a list of synchronouse ones,
which return the result immediately:

  * `GET /id`: returns your wallet ID in plain text.

  * `GET /balance`: returns the current balance of the wallet in "zents" (1 ZLD equals to 2^32 zents).
    If the wallet is absent on the server, there will be non-200 response code
    and maybe you need to call `/pull`. It's impossible to check the balance
    of the wallet, if the server doesn't have a copy of the wallet. The WTS
    server has to pull your wallet from the network first.

  * `GET /find`: finds and returns all transactions in the wallet that match the criteria.
    You can specify the criteria in the query string. For example,
    to find all transactions that were sent from the wallet
    `012345670.+` with the details `Hello!`
    (they both are regular expressions):
    `/find?bnf=012345670.%2B&details=Hello!`.
    You can match by all transaction fields (see the [White Paper](https://papers.zold.io/wp.pdf)).
    The result is a plain text list of transactions (not JSON).

  * `GET /txns.json`: returns a full list of transactions in the wallet, in JSON.
    You can specify the sorting order via `sort=asc` or `sort=desc`.

  * `GET /head.json`: returns the head of the wallet, which includes
    its ID, the balance, taxes, the size, and some other attributes; the
    full list of them may vary.

  * `GET /job`: checks the status of the jobs, expecting `id` as a query argument.
    Returns `200` and plain text `OK` if the job is completed.
    Returns `200` and plain text `Running` if the job is still in progress.
    Returns `200` and a full stack trace as plain text if the job is finished with an exception.
    Returns `404` if there is no such job.
    You may also want to use `/job.json` to get more information, in JSON.

  * `GET /output`: returns the entire log of a particular job, expecting `id` as a query argument;
    the HTTP header `X-Zold-JobStatus` will contain either `OK`, `Running`, or `Error`,
    depending on the status of the job.

  * `GET /job.json`: returns a simple JSON document with full information about
    a particular job, expecting `id` as a query argument
    (the JSON may also contain some additional data, for example, when you send
    a payment via `/do-pay` it will contain `txn` with the ID of the transaction
    just sent):

```json
{
  "id": "sjks-8sjs-sjUJs-sjkIIL",
  "status": "OK",
  "output_length": 15362,
  "error_message": "something went wrong...",
  "tid": "000111122223333:76"
}
```

  * `GET /id_rsa`: returns private RSA key of the user, expecting the
    [keygap](https://blog.zold.io/2018/07/18/keygap.html) as an argument.

  * `GET /keygap`: returns the [keygap](https://blog.zold.io/2018/07/18/keygap.html)
    of the user, if it's still not confirmed (as plain text).
    You have to show it to the client and make
    sure the client confirms that the keygap is safely stored, if you are
    managing the account of the user on their behalf.

  * `GET /do-confirm`: removes the [keygap](https://blog.zold.io/2018/07/18/keygap.html)
    from the database and returns `200` if everything is OK. If the user
    has already confirmed the keygap, this request will return a non-`200` response.

  * `GET /confirmed`: returns `yes` or `no`, depending on the status of the user---whether
    he has already confirmed his [keygap](https://blog.zold.io/2018/07/18/keygap.html)
    or not.

  * `GET /rate.json`: returns JSON document with all the data you can
    find [here](https://wts.zold.io/rate). If the data is not ready yet,
    you will still get a JSON document, but it will have `valid`
    attribute set to `false`. The only valid attribute there will be
    `effective_rate`. Here is a live [example](https://wts.zold.io/rate.json).

  * `GET /usd_rate`: returns current rate of ZLD in USD.

  * `GET /txn.json`: retrieves a single transaction details in JSON,
    expecting `tid` as a single query parameter (wallet ID + `:` + transaction ID).
    However, this information is not secure enough. This is just the data
    from the "general ledger," don't rely on it.

These entry points, just like the `/do-pay` explained above, are asynchronous.
In each of them you should expect `200` response with the `X-Zold-Job`
header inside. Using that job ID you can check the status of the job
as explained above in `/job.json`.

  * `GET /pull`: asks the server to pull your wallet from the network. This is
    a pretty fast and safe operation, you can do it every time before
    reading the wallet content, like finding transactions or checking the
    balance. If the wallet already exists on our server, there will
    be no pull from the network. If you really want to pull, no matter what,
    add `force=true`.

  * `GET /create`: creates a new wallet, assigns a new wallet ID to the user,
    leaving the keygap and private RSA key the same.

Make sure you always use the `noredirect=1` query parameter. Without it
you may get unpredictable response codes, like 302/303, and an HTML document
in the response body.

## Callback API

If you want to integrate Zold into your website or mobile app, where your
customers are sending payments to you, you may try our Callback API. First, you
send a `GET` request to `/wait-for` and specify:

  * `wallet`: the ID of the wallet you expect payments to (your wallet, if not provided)
  * `prefix`: the prefix you expect them to arrive to (get it at `/invoice.json` first)
  * `regexp`: the regular expression to match payment details, e.g. `pizza$` (the text has to end with `pizza`)
  * `uri`: the URI where the callback should arrive once we see the payment
  * `token`: the secret we will return back to you (up to 128 chars)
  * `repeat`: set to `true` if you want it to re-create itself right after it's matched
  * `forever`: set to `true` if you want it to never expire

If your callback is registered, you will receive `200` response of time `text/plain`
with the ID of the callback in the body.

Once the payment arrives, your URI will receive a `GET` request from us
with the following query arguments:

  * `callback`: the ID of the callback
  * `tid`: the unique ID of the transaction in the entire network
  * `login`: the user name of the owner of this callback
  * `regexp`: the regular expression just matched
  * `wallet`: the ID of the wallet that is receiving the payment
  * `id`: the transaction ID
  * `prefix`: the prefix just matched
  * `source`: the ID of the wallet that is sending the payment
  * `amount`: the amount in zents (always positive)
  * `details`: the details of the payment
  * `token`: the secret token you provided when registering the callback

Your callback has to return `200` and `OK` as a text. Unless it happens,
our server will send you another `GET` request in 5 minutes and will
keep doing that for 24 hours. Then it will give up, and will be deleted.

If your callback is never matched, it will be removed from the system
in 24 hours (unless you set `forever` to `true`).

You may register up to a certain amount of callbacks in one account
(check for the actual limit in the [Callbacks](https://wts.zold.io/callbacks)
tab in your account). The full list
of your registered callbacks and already matched ones you can find in the
[Callback](https://wts.zold.io/callbacks) tab of your account.

A more detailed explanation you may find in this blog post:
[How to Integrate](https://blog.zold.io/2019/03/11/how-to-integrate.html).

## Mobile API

If you want to create a mobile client, you may use our mobile API with a few
access points (the phone should be in
[E.164](https://en.wikipedia.org/wiki/E.164) format, numbers only):

  * `GET /mobile/send?phone=15551234567&noredirect=1`:
    returns `200` if the SMS has been sent to the user with the authentication code.
    If something is wrong, a non-200 code will be returned.

  * `GET /mobile/token?phone=15551234567&code=6666&noredirect=1`:
    returns `200` and the API access token in the body.
    The `code` is the code from the SMS.
    If something is wrong, a non-200 code will be returned

Then, you have to use `/do-confirm` and `/keygap` (see above) to confirm
the account of the user. Then, when you have the API token,
you can manage the account of the user,
using the `X-Zold-Wts` HTTP header (see above).

## Sandbox

You may want to experiment with the API in a sandbox mode. Just
login using this URL: https://wts.zold.io/sandbox. You
won't be able to send any payments our or to do any manipulations with
the real network, but you can play with all available features. It is
perfectly safe, you won't damage anything.

## How to Contribute

First, install
[Java 8+](https://java.com/en/download/),
[Maven 3.2+](https://maven.apache.org/),
[Ruby 2.3+](https://www.ruby-lang.org/en/documentation/installation/),
[Rubygems](https://rubygems.org/pages/download),
and
[Bundler](https://bundler.io/).
Then:

```bash
$ bundle update
$ bundle exec rake --quiet
```

The build has to be clean. If it's not, [submit an issue](https://github.com/zold-io/out/issues).

Then, make your changes, make sure the build is still clean,
and [submit a pull request](https://www.yegor256.com/2014/04/15/github-guidelines.html).

In order to run a single test:

```bash
$ bundle exec rake run
```

Then, in another terminal:

```bash
$ bundle exec ruby test/test_item.rb -n test_create_and_read
```

Then, if you want to test the UI, open `http://localhost:4567` in your browser,
and login, if necessary, by adding `?glogin=tester` to the URL.

Should work.
