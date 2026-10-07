#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."
python3 tests/trade-journal/run_tests.py

python3 scripts/build-journal-template.py --check
node tests/trade-journal/report_tests.js
node tests/trade-journal/notes_tests.js
node tests/trade-journal/notebook_tests.js
