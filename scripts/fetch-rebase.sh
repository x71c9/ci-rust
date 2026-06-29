#!/usr/bin/env bash

set -euo pipefail

git fetch origin master
git fetch origin master --tags
git rebase origin/master
