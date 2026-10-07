#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."
out="$(mktemp -d /tmp/pa-reversal-trader-tests.XXXXXX)"
trap 'rm -rf "$out"' EXIT
python3 - "$out" <<'PY'
from pathlib import Path
import re,sys
out=Path(sys.argv[1])
core=Path('MQL5/Experts/PAReversalTrader/PATradeCore.mqh').read_text()
core=core.replace('#include "../../Indicators/PAReversal/PAReversalCore.mqh"','#include "PAReversalCore.mqh"')
core=core.replace('#include "../ScalpCalculator/ScalpCore.mqh"','#include "ScalpCore.mqh"')
core=re.sub(r'const (PABar|PAConfirmedSwing) &(\w+)\[\]',r'const std::vector<\1> &\2',core)
core=re.sub(r'const double &(\w+)\[\]',r'const std::vector<double> &\1',core)
core=re.sub(r'(PABar|PAConfirmedSwing) &(\w+)\[\]',r'std::vector<\1> &\2',core)
core=core.replace('PAConfirmedSwing swings[];','std::vector<PAConfirmedSwing> swings;')
core=core.replace('double ema_values[];','std::vector<double> ema_values;')
(out/'PATradeCore.mqh').write_text(core)
(out/'PAReversalCore.mqh').write_text(Path('MQL5/Indicators/PAReversal/PAReversalCore.mqh').read_text())
(out/'ScalpCore.mqh').write_text(Path('MQL5/Experts/ScalpCalculator/ScalpCore.mqh').read_text())
PY
clang++ -std=c++17 -Wall -Wextra -Werror -O2 -I "$out" tests/pa-reversal-trader/core_tests.cpp -o "$out/core-tests"
"$out/core-tests"
