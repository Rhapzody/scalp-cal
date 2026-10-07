#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."
engulf_test_bin="$(mktemp /tmp/engulf-tests.XXXXXX)"
trap 'rm -f "$engulf_test_bin"' EXIT
clang++ -std=c++17 -Wall -Wextra -Werror -O2 tests/instant-engulf/engulf_tests.cpp -o "$engulf_test_bin"
"$engulf_test_bin"
