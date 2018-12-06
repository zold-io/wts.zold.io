<img src="http://www.zold.io/logo.svg" width="92px" height="92px"/>

[![Donate via Zerocracy](https://www.0crat.com/contrib-badge/CB28FH2NR.svg)](https://www.0crat.com/contrib/CB28FH2NR)

[![EO principles respected here](http://www.elegantobjects.org/badge.svg)](http://www.elegantobjects.org)
[![Managed by Zerocracy](https://www.0crat.com/badge/CAZPZR9FS.svg)](https://www.0crat.com/p/CAZPZR9FS)
[![DevOps By Rultor.com](http://www.rultor.com/b/zold-io/out)](http://www.rultor.com/p/zold-io/out)
[![We recommend RubyMine](http://www.elegantobjects.org/rubymine.svg)](https://www.jetbrains.com/ruby/)

[![Build Status](https://travis-ci.org/zold-io/wts.zold.io.svg)](https://travis-ci.org/zold-io/wts.zold.io)
[![PDD status](http://www.0pdd.com/svg?name=zold-io/wts.zold.io)](http://www.0pdd.com/p?name=zold-io/wts.zold.io)
[![Test Coverage](https://img.shields.io/codecov/c/github/zold-io/wts.zold.io.svg)](https://codecov.io/github/zold-io/wts.zold.io?branch=master)
[![Maintainability](https://api.codeclimate.com/v1/badges/25b798dc13147f13bb59/maintainability)](https://codeclimate.com/github/zold-io/wts.zold.io/maintainability)

Here is the [White Paper](https://papers.zold.io//wp.pdf).

Join our [Telegram group](https://t.me/zold_io) to discuss it all live.

The license is [MIT](https://github.com/zold-io/wts.zold.io/blob/master/LICENSE.txt).

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
$ rake
```

The build has to be clean. If it's not, [submit an issue](https://github.com/zold-io/out/issues).

Then, make your changes, make sure the build is still clean,
and [submit a pull request](https://www.yegor256.com/2014/04/15/github-guidelines.html).

In order to run a single test:

```bash
$ rake run
```

Then, in another terminal:

```bash
$ ruby test/test_item.rb -n test_create_and_read
```
