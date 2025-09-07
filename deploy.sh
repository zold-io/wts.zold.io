#!/usr/bin/env bash
# SPDX-FileCopyrightText: Copyright (c) 2018-2025 Zerocracy
# SPDX-License-Identifier: MIT

set -e
set -x

cd "$(dirname "$0")"
# bundle up
# rake
sed -i -s 's|Gemfile.lock||g' .gitignore
cp /code/home/assets/zold/wts-config.yml config.yml
git add config.yml
git add Gemfile.lock
git add .gitignore
git commit -m 'config.yml for heroku'
trap 'git reset HEAD~1 && rm config.yml && git checkout -- .gitignore' EXIT
git push heroku master -f
