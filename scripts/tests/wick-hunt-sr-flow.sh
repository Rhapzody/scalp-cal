#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."
ws_test_dir="$(mktemp -d /tmp/wick-hunt-sr-tests.XXXXXX)"
trap 'rm -rf "$ws_test_dir"' EXIT
python3 - "$ws_test_dir" <<'PY'
from pathlib import Path
import re
import sys
source = Path('MQL5/Indicators/WickHuntSRFlow/WickHuntSRFlow.mq5').read_text()
parts = []
for signature in ('bool ReplayHigher(', 'bool LoadContext(', 'bool ReplayLower(', 'string ScenarioText(', 'void MapOutput(', 'void UpdateLive(', 'void OnTimer(', 'int OnCalculate('):
    start = source.index(signature)
    end = source.index('{', start) + 1
    depth = 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    part = source[start:end]
    part = re.sub(r'const (datetime|double|long|int) &(\w+)\[\]', r'const std::vector<\1> &\2', part)
    part = re.sub(r'MqlRates (\w+)\[\]', r'std::vector<MqlRates> \1', part)
    parts.append(part)
Path(sys.argv[1], 'indicator_under_test.hpp').write_text('\n'.join(parts))
context = Path('MQL5/Indicators/WickHuntSRFlow/WickHuntContextCore.mqh').read_text()
context = re.sub(r'const MSBar &(\w+)\[\]', r'const std::vector<MSBar> &\1', context)
Path(sys.argv[1], 'WickHuntContextCore.hpp').write_text(context)
flow = Path('MQL5/Indicators/WickHuntSRFlow/EngulfImbalanceCore.mqh').read_text()
flow = re.sub(r'const (WHBar|int|double) &(\w+)\[\]', r'const std::vector<\1> &\2', flow)
Path(sys.argv[1], 'EngulfImbalanceCore.mqh').write_text(flow)
original = Path('MQL5/Indicators/MACDSwingCount/SwingCore.mqh').read_bytes()
copied = Path('MQL5/Indicators/WickHuntSRFlow/SwingCore.mqh').read_bytes()
if original != copied:
    raise SystemExit('Histogram swing core differs from MACDSwingCount')
for name in ('FVGCore.mqh', 'EngulfImbalanceCore.mqh', 'EngulfFlowCore.mqh'):
    if (Path('MQL5/Indicators/EngulfImbalanceFlow') / name).read_bytes() != (Path('MQL5/Indicators/WickHuntSRFlow') / name).read_bytes():
        raise SystemExit(f'{name} differs from the original flow core')
PY
clang++ -std=c++17 -Wall -Wextra -Werror -Wno-unused-parameter -O2 \
  -I "$ws_test_dir" -I MQL5/Indicators/WickHuntSRFlow tests/wick-hunt-sr-flow/flow_tests.cpp -o "$ws_test_dir/ws-tests"
"$ws_test_dir/ws-tests"
