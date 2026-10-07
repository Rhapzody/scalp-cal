#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."
test_dir="$(mktemp -d /tmp/opening-range-retest.XXXXXX)"
trap 'rm -rf "$test_dir"' EXIT
python3 - "$test_dir" <<'PY'
from pathlib import Path
import re,sys
s=Path('MQL5/Indicators/OpeningRangeRetest/OpeningCore.mqh').read_text()
s=re.sub(r'const ORBar &(\w+)\[\]',r'const std::vector<ORBar> &\1',s)
s=re.sub(r'ORSignal &(\w+)\[\]',r'std::vector<ORSignal> &\1',s)
Path(sys.argv[1],'OpeningCore.mqh').write_text(s)
PY
clang++ -std=c++17 -Wall -Wextra -Werror -O2 -I "$test_dir" tests/opening-range-retest/core_tests.cpp -o "$test_dir/core"
"$test_dir/core"
