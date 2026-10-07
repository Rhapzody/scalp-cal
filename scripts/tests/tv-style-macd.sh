#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."
macd_test_dir="$(mktemp -d /tmp/macd-tests.XXXXXX)"
trap 'rm -rf "$macd_test_dir"' EXIT
python3 - "$macd_test_dir" <<'PY'
from pathlib import Path
import sys
text=Path('MQL5/Indicators/TVStyleMACD/TVStyleMACD.mq5').read_text()
start=text.index('void CalculateBar(')
body=text.index('{',start)
depth=1
end=body+1
while depth:
    depth += (text[end]=='{')-(text[end]=='}')
    end += 1
Path(sys.argv[1],'macd_bar_under_test.hpp').write_text(text[start:end]+'\n')
PY
clang++ -std=c++17 -Wall -Wextra -Werror -O2 -I "$macd_test_dir" tests/tv-style-macd/macd_tests.cpp -o "$macd_test_dir/macd-tests"
"$macd_test_dir/macd-tests"
