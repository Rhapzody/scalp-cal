#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."
pa_test_dir="$(mktemp -d /tmp/pa-reversal-tests.XXXXXX)"
trap 'rm -rf "$pa_test_dir"' EXIT
python3 - "$pa_test_dir" <<'PY'
from pathlib import Path
import re
import sys
source = Path('MQL5/Indicators/PAReversal/PAReversal.mq5').read_text()
functions = []
for signature in ('void CalculatePABar(', 'int OnCalculate('):
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
Path(sys.argv[1], 'pa_indicator_under_test.hpp').write_text('\n'.join(functions))
PY
clang++ -std=c++17 -Wall -Wextra -Werror -Wno-unused-parameter -O2 \
  -I "$pa_test_dir" tests/pa-reversal/pa_reversal_tests.cpp -o "$pa_test_dir/pa-tests"
"$pa_test_dir/pa-tests"
