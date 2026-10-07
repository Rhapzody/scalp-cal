#!/usr/bin/env python3
"""Package existing, successfully compiled MT5 products. Does not run a terminal."""
import argparse
import datetime
import hashlib
import json
import re
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def package(key, product):
    source = ROOT / product['source']
    output = ROOT / 'dist' / product['category'] / key
    docs = ROOT / 'docs' / product['category'] / key
    binary = source / (product['name'] + '.ex5')
    code = sorted(source.glob('*.mq*'))
    shared_code = [ROOT / name for name in product.get('extra_files', [])
                   if Path(name).suffix in ('.mq5', '.mqh')]
    log_path = output / 'compile.log'
    if not code or not binary.exists() or not log_path.exists():
        raise RuntimeError(f'{key}: compile first with sh scripts/compile-macos.sh {key}')
    if binary.stat().st_mtime < max(p.stat().st_mtime for p in code + shared_code):
        raise RuntimeError(f'{key}: EX5 is older than source; compile again')
    log = log_path.read_text(encoding='utf-16')
    if 'Result: 0 errors, 0 warnings' not in log:
        raise RuntimeError(f'{key}: compiler log does not show a clean build')
    version = re.search(r'#property\s+version\s+"([^"]+)"', (source / (product['name'] + '.mq5')).read_text()).group(1)
    archive_name = f'{product["name"]}-{version}.zip'
    prefix = f'{product["name"]}-{version}/'
    entries = {}

    def add(path, name=None):
        entries[name or str(path.relative_to(ROOT))] = path.read_bytes()

    for path in code + [binary]:
        add(path)
    for companion in product.get('companions', []):
        companion_source = ROOT / companion['source']
        companion_code = sorted(companion_source.glob('*.mq*'))
        companion_binary = companion_source / (companion['name'] + '.ex5')
        companion_log = output / ('compile-' + companion['name'] + '.log')
        if not companion_binary.exists() or not companion_log.exists():
            raise RuntimeError(f'{key}: compile companion {companion["name"]} first')
        if companion_binary.stat().st_mtime < max(p.stat().st_mtime for p in companion_code + shared_code):
            raise RuntimeError(f'{key}: companion binary is older than source')
        if 'Result: 0 errors, 0 warnings' not in companion_log.read_text(encoding='utf-16'):
            raise RuntimeError(f'{key}: companion did not compile cleanly')
        for path in companion_code + [companion_binary, companion_log, companion_log.with_suffix('.txt')]:
            add(path)
    for name in product.get('extra_files', []):
        add(ROOT / name)
    for path in sorted(docs.glob('*.md')):
        add(path)
        add(path, path.name)
    for directory in product['tests']:
        for path in sorted((ROOT / directory).iterdir()):
            if path.is_file():
                add(path)
    tooling = ['scripts/test.sh', 'scripts/compile-macos.sh', 'scripts/package.py']
    if product['tests']:
        tooling.append(f'scripts/tests/{key}.sh')
    for name in tooling:
        add(ROOT / name)
    entries['scripts/products.json'] = (json.dumps({key: product}, indent=2) + '\n').encode()
    entries[f'dist/{product["category"]}/{key}/compile.log'] = log_path.read_bytes()
    entries[f'dist/{product["category"]}/{key}/compile.txt'] = log.encode()
    manifest = {
        'product': key, 'name': product['name'], 'version': version,
        'packaged_at': datetime.datetime.now().astimezone().isoformat(),
        'compiler_result': '0 errors, 0 warnings',
        'documented_test_checks': product['checks'],
        'note': 'Packaging does not run tests or verify native MT5 UI/trade execution.',
        'sha256': {name: hashlib.sha256(data).hexdigest() for name, data in entries.items()},
    }
    manifest_data = (json.dumps(manifest, indent=2) + '\n').encode()
    entries['build-manifest.json'] = manifest_data
    temp = output / (archive_name + '.tmp')
    with zipfile.ZipFile(temp, 'w', zipfile.ZIP_DEFLATED) as archive:
        for name, data in entries.items():
            archive.writestr(prefix + name, data)
    with zipfile.ZipFile(temp) as archive:
        if archive.testzip() is not None:
            raise RuntimeError(f'{key}: ZIP integrity failed')
    temp.replace(output / archive_name)
    (output / 'build-manifest.json').write_bytes(manifest_data)
    (output / binary.name).write_bytes(binary.read_bytes())
    (output / 'compile.txt').write_text(log)
    print(f'{key}: {output.relative_to(ROOT) / archive_name} ({len(entries)} files)')


if __name__ == '__main__':
    products = json.loads((ROOT / 'scripts/products.json').read_text())
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('products', nargs='*', default=['all'])
    args = parser.parse_args()
    chosen = list(products) if args.products == ['all'] else args.products
    for key in chosen:
        if key not in products:
            parser.error('Unknown product: ' + key)
    for key in chosen:
        package(key, products[key])
