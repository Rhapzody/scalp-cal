#!/usr/bin/env python3
"""Compile the integrated executor against MT5 mocks; never connects to MT5."""
from pathlib import Path
import subprocess
import tempfile
root=Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix='scalp-engulf-tests-') as temp:
    header=Path(temp)/'ScalpEngulf.mqh'
    # C++ requires the fixed buffer size; production MQL uses a series array.
    source=(root/'MQL5/Experts/ScalpCalculator/ScalpEngulf.mqh').read_text()
    header.write_text(source.replace('MqlRates pair[];', 'MqlRates pair[2];'))
    timing=Path(temp)/'EngulfTiming.mqh'
    timing.write_text((root/'MQL5/Experts/ScalpCalculator/EngulfTiming.mqh').read_text().replace('MqlRates pair[];', 'MqlRates pair[2];'))
    binary=Path(temp)/'test'
    subprocess.run(['clang++','-std=c++17','-Wall','-Wextra','-Werror','-Wno-implicitly-unsigned-literal','-O2',
                    f'-DSCALP_ENGULF_ENGINE_HEADER="{header}"',f'-DSCALP_ENGULF_TIMING_HEADER="{timing}"',
                    str(root/'tests/scalp-calculator/engulf_panel_tests.cpp'),'-o',str(binary)],check=True)
    subprocess.run([str(binary)],check=True)
