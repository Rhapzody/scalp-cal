#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."
ts_test_dir="$(mktemp -d /tmp/trend-sweep-tests.XXXXXX)"
trap 'rm -rf "$ts_test_dir"' EXIT
python3 - "$ts_test_dir" <<'PY'
from pathlib import Path
import re,sys
source=Path('MQL5/Indicators/TrendSweepReclaim/SweepCore.mqh').read_text()
source=re.sub(r'const TSBar &(\w+)\[\]',r'const std::vector<TSBar> &\1',source)
source=re.sub(r'TSSignal &(\w+)\[\]',r'std::vector<TSSignal> &\1',source)
Path(sys.argv[1],'SweepCore.mqh').write_text(source)
source=Path('MQL5/Indicators/TrendSweepReclaim/TrendSweepReclaim.mq5').read_text()
functions=[]
for signature in ('int TSChartIndex(', 'int OnCalculate('):
    start=source.index(signature);end=source.index('{',start)+1;depth=1
    while depth:
        depth+=(source[end]=='{')-(source[end]=='}');end+=1
    function=re.sub(r'const (datetime|double|long|int) &(\w+)\[\]',r'const std::vector<\1> &\2',source[start:end])
    function=function.replace('MqlRates rates[];', 'std::vector<MqlRates> rates;').replace('(string)s.time','std::to_string(s.time)').replace('(string)total','std::to_string(total)')
    functions.append(function)
Path(sys.argv[1],'indicator_under_test.hpp').write_text('\n'.join(functions))
PY
clang++ -std=c++17 -Wall -Wextra -Werror -O2 -I "$ts_test_dir" tests/trend-sweep-reclaim/core_tests.cpp -o "$ts_test_dir/core"
"$ts_test_dir/core"
clang++ -std=c++17 -Wall -Wextra -Werror -Wno-unused-parameter -O2 -I "$ts_test_dir" tests/trend-sweep-reclaim/indicator_tests.cpp -o "$ts_test_dir/indicator"
"$ts_test_dir/indicator"
