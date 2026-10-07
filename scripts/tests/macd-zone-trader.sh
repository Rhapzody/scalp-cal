#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."
zone_trader_test_dir="$(mktemp -d /tmp/macd-zone-trader-tests.XXXXXX)"
trap 'rm -rf "$zone_trader_test_dir"' EXIT
python3 - "$zone_trader_test_dir" <<'PY'
from pathlib import Path
import re
import sys
root = Path('MQL5/Experts/MACDZoneTrader')
output = Path(sys.argv[1])
for path in root.glob('*.mqh'):
    source = path.read_text()
    source = re.sub(r'const (MSBar|EATarget) &(\w+)\[\]', r'const std::vector<\1> &\2', source)
    source = re.sub(r'(RPEntry|EATarget) &(\w+)\[\]', r'std::vector<\1> &\2', source)
    source = source.replace('RPEntry entries[];', 'std::vector<RPEntry> entries;')
    (output / path.name).write_text(source)
for original, names in [
    ('MQL5/Indicators/MACDZonePullback', ['SwingCore.mqh', 'FVGCore.mqh', 'PullbackCore.mqh']),
    ('MQL5/Experts/ScalpCalculator', ['ScalpCore.mqh', 'ScalpBroker.mqh'])
]:
    for name in names:
        path = Path(original) / name
        if path.exists():
            assert path.read_bytes() == (root / name).read_bytes(), f'{name}: source drift'
source = (root / 'MACDZoneTrader.mq5').read_text()
functions = []
for signature in ('bool EAFresh(', 'bool EAHasExposure(', 'string EAMarker(', 'int EALock(',
                  'void EAUnlock(', 'bool EAHalted(', 'bool EAAttempted(', 'bool EAMarkAttempt(', 'void EAClearHalt('):
    start = source.index(signature)
    end = source.index('{', start) + 1
    depth = 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    function = source[start:end].replace('(string)InpMagicNumber', 'std::to_string(InpMagicNumber)')
    functions.append(function)
(output / 'host_under_test.hpp').write_text('\n'.join(functions))
start = source.index('void OnTick(')
end = source.index('{', start) + 1
depth = 1
while depth:
    depth += (source[end] == '{') - (source[end] == '}')
    end += 1
tick = source[start:end].replace('EATarget targets[];', 'std::vector<EATarget> targets;')
(output / 'tick_under_test.hpp').write_text(tick)
PY
clang++ -std=c++17 -Wall -Wextra -Werror -Wno-unused-parameter -O2 \
  -I "$zone_trader_test_dir" tests/macd-zone-trader/plan_tests.cpp -o "$zone_trader_test_dir/plan-tests"
"$zone_trader_test_dir/plan-tests"
clang++ -std=c++17 -Wall -Wextra -Werror -Wno-unused-parameter -O2 \
  -DSCALP_BROKER_HEADER='"ScalpBroker.mqh"' -I "$zone_trader_test_dir" \
  tests/macd-zone-trader/execution_tests.cpp -o "$zone_trader_test_dir/execution-tests"
"$zone_trader_test_dir/execution-tests"
