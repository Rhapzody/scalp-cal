#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."
wh_test_dir="$(mktemp -d /tmp/engulf-flow-tests.XXXXXX)"
trap 'rm -rf "$wh_test_dir"' EXIT
python3 - "$wh_test_dir" <<'PY'
from pathlib import Path
import re
import sys
source = Path('MQL5/Indicators/EngulfFlow/EngulfFlow.mq5').read_text()
functions = []
for signature in ('datetime WHServerNow(', 'datetime WHBarClose(', 'void WHWrite(', 'void WHUpdateEMA(', 'int WHSignalAt(', 'void WHRefreshLive(', 'void OnTimer(', 'int OnCalculate('):
    start = source.index(signature)
    end = source.index('{', start) + 1
    depth = 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    function = source[start:end]
    # Adapt only MQL array parameter syntax to C++ vectors; keep function bodies.
    function = re.sub(r'const (datetime|double|long|int) &(\w+)\[\]',
                      r'const std::vector<\1> &\2', function)
    functions.append(function)
Path(sys.argv[1], 'wh_indicator_under_test.hpp').write_text('\n'.join(functions))
PY
clang++ -std=c++17 -Wall -Wextra -Werror -Wno-unused-parameter -O2 \
  -I "$wh_test_dir" tests/engulf-flow/engulf_flow_tests.cpp -o "$wh_test_dir/wh-tests"
"$wh_test_dir/wh-tests"
