#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."
test_dir="$(mktemp -d /tmp/opening-range-trader.XXXXXX)"
trap 'rm -rf "$test_dir"' EXIT
python3 - "$test_dir" <<'PY'
from pathlib import Path
import re,sys
core=Path('MQL5/Indicators/OpeningRangeRetest/OpeningCore.mqh').read_text()
core=re.sub(r'const ORBar &(\w+)\[\]',r'const std::vector<ORBar> &\1',core)
core=re.sub(r'ORSignal &(\w+)\[\]',r'std::vector<ORSignal> &\1',core)
Path(sys.argv[1],'OpeningCore.mqh').write_text(core)
Path(sys.argv[1],'ScalpCalculator').mkdir()
Path(sys.argv[1],'ScalpCalculator','ScalpCore.mqh').write_text(Path('MQL5/Experts/ScalpCalculator/ScalpCore.mqh').read_text())
plan=Path('MQL5/Experts/OpeningRangeTrader/TradePlanCore.mqh').read_text()
plan=plan.replace('#include "../ScalpCalculator/ScalpCore.mqh"','#include "ScalpCalculator/ScalpCore.mqh"')
plan=re.sub(r'const ORBar &(\w+)\[\]',r'const std::vector<ORBar> &\1',plan)
plan=re.sub(r'ORTarget &(\w+)\[\]',r'std::vector<ORTarget> &\1',plan)
plan=plan.replace('ORSignal entries[];','std::vector<ORSignal> entries;')
plan=plan.replace('string &reason','std::string &reason')
Path(sys.argv[1],'TradePlanCore.mqh').write_text(plan)
PY
clang++ -std=c++17 -Wall -Wextra -Werror -O2 -I "$test_dir" tests/opening-range-trader/plan_tests.cpp -o "$test_dir/plan"
"$test_dir/plan"
