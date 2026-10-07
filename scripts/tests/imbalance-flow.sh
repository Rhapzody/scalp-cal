#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."
fvg_test_dir="$(mktemp -d /tmp/imbalance-flow-tests.XXXXXX)"
trap 'rm -rf "$fvg_test_dir"' EXIT
python3 - "$fvg_test_dir" <<'PY'
from pathlib import Path
import re
import sys
source = Path('MQL5/Indicators/ImbalanceFlow/ImbalanceFlow.mq5').read_text()
core=Path('MQL5/Indicators/ImbalanceFlow/DisplacementCore.mqh').read_text()
core=re.sub(r'const (FVGBar|long) &(\w+)\[\]', r'const std::vector<\1> &\2',core)
core=core.replace('double bodies[];', 'std::vector<double> bodies;')
Path(sys.argv[1], 'dp_core_under_test.hpp').write_text(core)
functions = []
for signature in ('bool RebuildFVG(', 'int OnCalculate(', 'void OnDeinit('):
    start = source.index(signature)
    end = source.index('{', start) + 1
    depth = 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    function = re.sub(r'const (datetime|double|long|int) &(\w+)\[\]',
                      r'const std::vector<\1> &\2', source[start:end])
    function=re.sub(r'(FVGBar|FVGZone|long|int) (\w+)\[\]',r'std::vector<\1> \2',function)
    function=function.replace('sources,kinds[],used[]','sources,kinds,used')
    functions.append(function)
Path(sys.argv[1], 'fvg_indicator_under_test.hpp').write_text('\n'.join(functions))
PY
clang++ -std=c++17 -Wall -Wextra -Werror -Wno-unused-parameter -O2 \
  -I "$fvg_test_dir" -I MQL5/Indicators/ImbalanceFlow tests/imbalance-flow/fvg_tests.cpp -o "$fvg_test_dir/fvg-tests"
"$fvg_test_dir/fvg-tests"
