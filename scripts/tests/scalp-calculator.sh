#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."
test_bin="$(mktemp /tmp/scalp-core-tests.XXXXXX)"
trap 'rm -f "$test_bin"' EXIT
clang++ -std=c++17 -Wall -Wextra -Werror -O2 tests/scalp-calculator/core_tests.cpp -o "$test_bin"
"$test_bin"
clang++ -std=c++17 -Wall -Wextra -Werror -O2 tests/scalp-calculator/broker_tests.cpp -o "$test_bin"
"$test_bin"
python3 tests/scalp-calculator/ui_layout_tests.py
python3 tests/scalp-calculator/run_engulf_panel_tests.py
