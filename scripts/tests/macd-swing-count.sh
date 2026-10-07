#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."
ms_test_dir="$(mktemp -d /tmp/macd-swing-tests.XXXXXX)"
trap 'rm -rf "$ms_test_dir"' EXIT
python3 - "$ms_test_dir" <<'PY'
from pathlib import Path
import re
import sys
source = Path('MQL5/Indicators/MACDSwingCount/MACDSwingCount.mq5').read_text()
parts = [source[source.index('double SwingHigh[]'):source.index('void ClearBuffers()')]]
for signature in ('void ClearBuffers(', 'void ClearBar(', 'bool CalculateClosedBar(', 'int OnCalculate('):
    start = source.index(signature)
    end = source.index('{', start) + 1
    depth = 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    parts.append(source[start:end])
text = '\n'.join(parts)
text = re.sub(r'const (datetime|double|long|int) &(\w+)\[\]',
              r'const std::vector<\1> &\2', text)
text = re.sub(r'\b(double|MSEvent) ([^;\n]*\[\][^;\n]*);',
              lambda m: 'std::vector<' + m[1] + '> ' + m[2].replace('[]', '') + ';', text)
Path(sys.argv[1], 'indicator_under_test.hpp').write_text(text)
start = source.index('void RenderSRLevels(')
end = source.index('{', start) + 1
depth = 1
while depth:
    depth += (source[end] == '{') - (source[end] == '}')
    end += 1
Path(sys.argv[1], 'sr_render_under_test.hpp').write_text(source[start:end])
PY
clang++ -std=c++17 -Wall -Wextra -Werror -Wno-unused-parameter -O2 \
  -I "$ms_test_dir" tests/macd-swing-count/swing_tests.cpp -o "$ms_test_dir/swing-tests"
"$ms_test_dir/swing-tests"
clang++ -std=c++17 -Wall -Wextra -Werror -Wno-unused-parameter -O2 \
  -I "$ms_test_dir" tests/macd-swing-count/sr_render_tests.cpp -o "$ms_test_dir/sr-tests"
"$ms_test_dir/sr-tests"
