#!/usr/bin/env python3
"""Compile production MQL logic in a C++ MT5 mock; no terminal or trades."""
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
source_dir = ROOT / 'MQL5/Experts/TradeJournal'
code = (source_dir / 'JournalCore.mqh').read_text() + '\n' + (source_dir / 'TradeJournal.mq5').read_text() + '\nconst string JR_TEMPLATE=\"__JOURNAL_DATA__\";\n' + (ROOT / 'MQL5/Scripts/TradeJournal/ExportJournalReport.mq5').read_text()
# Recorder must remain passive, including future changes.
for forbidden in ('OrderSend', 'OrderSendAsync', 'OrderCheck', 'CTrade', 'WebRequest', 'ShellExecute', 'ChartScreenShot'):
    assert not re.search(r'\b' + forbidden + r'\s*\(', code), forbidden
code = re.sub(r'^#property.*\n|^input group.*\n|^#include [^\n]+\n', '', code, flags=re.M)
code = re.sub(r'^input ', '', code, flags=re.M)
code = re.sub(r'\b(const )?(\w+) &(\w+)\[\]', lambda m: (m[1] or '') + 'std::vector<' + m[2] + '> &' + m[3], code)
code = re.sub(r'\b(TJState|TJQueued|JRPosition|MqlRates|ENUM_TIMEFRAMES|ulong|uchar|string) ((?:\w+\[\](?:,\w+\[\])*)+);',
              lambda m: 'std::vector<' + m[1] + '> ' + m[2].replace('[]', '') + ';', code)
# Enums preserve their names in CSV. Production MetaEditor checks real API types/constants.
groups = {
'ENUM_TIMEFRAMES': ['PERIOD_CURRENT','PERIOD_M1','PERIOD_M2','PERIOD_M3','PERIOD_M4','PERIOD_M5','PERIOD_M6','PERIOD_M10','PERIOD_M12','PERIOD_M15','PERIOD_M20','PERIOD_M30','PERIOD_H1','PERIOD_H2','PERIOD_H3','PERIOD_H4','PERIOD_H6','PERIOD_H8','PERIOD_H12','PERIOD_D1','PERIOD_W1','PERIOD_MN1'],
'ENUM_TRADE_TRANSACTION_TYPE': ['TRADE_TRANSACTION_ORDER_ADD','TRADE_TRANSACTION_ORDER_UPDATE','TRADE_TRANSACTION_ORDER_DELETE','TRADE_TRANSACTION_DEAL_ADD','TRADE_TRANSACTION_DEAL_UPDATE','TRADE_TRANSACTION_DEAL_DELETE','TRADE_TRANSACTION_HISTORY_ADD','TRADE_TRANSACTION_HISTORY_UPDATE','TRADE_TRANSACTION_HISTORY_DELETE','TRADE_TRANSACTION_POSITION','TRADE_TRANSACTION_REQUEST'],
'ENUM_DEAL_TYPE': ['DEAL_TYPE_BUY','DEAL_TYPE_SELL','DEAL_TYPE_BALANCE','DEAL_TYPE_COMMISSION','DEAL_TYPE_BUY_CANCELED'],
'ENUM_DEAL_ENTRY': ['DEAL_ENTRY_IN','DEAL_ENTRY_OUT','DEAL_ENTRY_INOUT','DEAL_ENTRY_OUT_BY'],
'ENUM_DEAL_REASON': ['DEAL_REASON_CLIENT','DEAL_REASON_MOBILE','DEAL_REASON_WEB','DEAL_REASON_EXPERT','DEAL_REASON_SL','DEAL_REASON_TP'],
'ENUM_ORDER_TYPE': ['ORDER_TYPE_BUY','ORDER_TYPE_SELL','ORDER_TYPE_BUY_LIMIT','ORDER_TYPE_SELL_LIMIT'],
'ENUM_ORDER_STATE': ['ORDER_STATE_STARTED','ORDER_STATE_PLACED','ORDER_STATE_PARTIAL','ORDER_STATE_FILLED','ORDER_STATE_CANCELED'],
'ENUM_POSITION_TYPE': ['POSITION_TYPE_BUY','POSITION_TYPE_SELL'],
'ENUM_POSITION_REASON': ['POSITION_REASON_CLIENT','POSITION_REASON_EXPERT'],
'ENUM_ORDER_REASON': ['ORDER_REASON_CLIENT','ORDER_REASON_EXPERT'],
'ENUM_ACCOUNT_MARGIN_MODE': ['ACCOUNT_MARGIN_MODE_RETAIL_HEDGING','ACCOUNT_MARGIN_MODE_RETAIL_NETTING'],
}
enums=''
for typ, values in groups.items():
    enums += 'enum '+typ+' {'+','.join(values)+'};\n'
    enums += 'string EnumToString('+typ+' v) { switch(v) {' + ''.join('case '+v+': return "'+v+'";' for v in values) + '} return "UNKNOWN"; }\n'
props=sorted(set(re.findall(r'\b(?:ACCOUNT|DEAL|POSITION|ORDER|TERMINAL|MQL)_[A-Z_]+\b',code)) - {v for vs in groups.values() for v in vs} - {'DEAL_HEADER'})
enums+='enum Properties {'+','.join(p+'='+str(i+100) for i,p in enumerate(props))+'};\n'
with tempfile.TemporaryDirectory(prefix='trade-journal-tests-') as temp:
    temp=Path(temp)
    (temp/'enums.hpp').write_text(enums)
    (temp/'production.hpp').write_text(code)
    binary=temp/'journal-tests'
    subprocess.run(['clang++','-std=c++17','-Wall','-Wextra','-Werror','-Wno-unused-parameter','-Wno-sign-compare','-O2','-I',str(temp),str(Path(__file__).with_name('journal_tests.cpp')),'-o',str(binary)],check=True)
    subprocess.run([str(binary)],check=True)
