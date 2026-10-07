#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."
pullback_test_dir="$(mktemp -d /tmp/macd-zone-pullback-tests.XXXXXX)"
trap 'rm -rf "$pullback_test_dir"' EXIT
python3 - "$pullback_test_dir" <<'PY'
from pathlib import Path
import re
import sys
root = Path('MQL5/Indicators/MACDZonePullback')
output = Path(sys.argv[1])
for name in ('SwingCore.mqh', 'FVGCore.mqh', 'PullbackCore.mqh'):
    source = (root / name).read_text()
    source = re.sub(r'const MSBar &(\w+)\[\]', r'const std::vector<MSBar> &\1', source)
    source = re.sub(r'RPEntry &(\w+)\[\]', r'std::vector<RPEntry> &\1', source)
    (output / name).write_text(source)
# Standalone packages carry identical cores but do not require the other indicators.
for original, name in [('MACDSwingCount', 'SwingCore.mqh'), ('ImbalanceFlow', 'FVGCore.mqh')]:
    path = Path('MQL5/Indicators') / original / name
    if path.exists():
        assert path.read_bytes() == (root / name).read_bytes(), f'{name}: shared core drift'
source = (root / 'MACDZonePullback.mq5').read_text()
functions = []
for signature in ('int ChartBar(', 'int OnCalculate('):
    start = source.index(signature)
    end = source.index('{', start) + 1
    depth = 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    function = re.sub(r'const (datetime|double|long|int) &(\w+)\[\]',
                      r'const std::vector<\1> &\2', source[start:end])
    functions.append(function)
(output / 'indicator_under_test.hpp').write_text('\n'.join(functions))
PY
clang++ -std=c++17 -Wall -Wextra -Werror -Wno-unused-parameter -O2 \
  -I "$pullback_test_dir" tests/macd-zone-pullback/pullback_tests.cpp -o "$pullback_test_dir/core-tests"
"$pullback_test_dir/core-tests"
clang++ -std=c++17 -Wall -Wextra -Werror -Wno-unused-parameter -O2 \
  -I "$pullback_test_dir" tests/macd-zone-pullback/indicator_tests.cpp -o "$pullback_test_dir/indicator-tests"
"$pullback_test_dir/indicator-tests"
