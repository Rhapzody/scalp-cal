#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
python3 - "$@" <<'PY'
import json, os, subprocess, sys, time, uuid
from pathlib import Path
root = Path.cwd()
products = json.loads((root / 'scripts/products.json').read_text())
requested = sys.argv[1:] or ['all']
selected = list(products) if requested == ['all'] else requested
if any(key not in products for key in selected):
    raise SystemExit('Choose all or: ' + ', '.join(products))
prefix = Path(os.environ.get('SCALP_WINE_PREFIX', str(Path.home() / 'Library/Application Support/net.metaquotes.wine.metatrader5')))
wine = Path(os.environ.get('SCALP_WINE_BIN', '/Applications/MetaTrader 5.app/Contents/SharedSupport/wine/bin/wine'))
editor = prefix / 'drive_c/Program Files/MetaTrader 5/metaeditor64.exe'
if not wine.is_file() or not editor.is_file():
    raise SystemExit('MetaEditor/Wine not found; set SCALP_WINE_PREFIX and SCALP_WINE_BIN.')
env = dict(os.environ, WINEPREFIX=str(prefix), WINEDEBUG='-all')
def win(path):
    return 'Z:' + str(path).replace('/', '\\')
for key in selected:
    product = products[key]
    targets = [dict(source=product['source'], name=product['name'])] + product.get('companions', [])
    for target in targets:
        source = root / target['source'] / (target['name'] + '.mq5')
        output = root / 'dist' / product['category'] / key
        output.mkdir(parents=True, exist_ok=True)
        stem = 'compile' if target['name'] == product['name'] else 'compile-' + target['name']
        log = output / (stem + '-' + uuid.uuid4().hex + '.log')
        print('Compiling', key, '/', target['name'], flush=True)
        subprocess.run([str(wine), str(editor), '/compile:' + win(source), '/log:' + win(log)],
                       env=env, timeout=120, check=False)
        deadline = time.monotonic() + 60
        result = ''
        while time.monotonic() < deadline:
            if log.exists():
                result = log.read_text(encoding='utf-16', errors='replace')
                if 'Result:' in result:
                    break
            time.sleep(.25)
        if 'Result:' not in result:
            raise SystemExit(f'No completed compiler result; inspect {log}')
        log.replace(output / (stem + '.log'))
        (output / (stem + '.txt')).write_text(result, encoding='utf-8')
        print(next(line for line in result.splitlines() if 'Result:' in line), flush=True)
        if 'Result: 0 errors, 0 warnings' not in result:
            raise SystemExit(f'Compilation needs attention: {output / (stem + ".txt")}')
PY
