#!/usr/bin/env python3
"""Compare study order levels against actual InstantEngulf pure price helpers."""
import csv
import hashlib
import json
import math
from pathlib import Path
import subprocess
import tempfile

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[2]
EA=ROOT/'MQL5/Experts/InstantEngulf'


def main():
    events={r['event_id']:r for r in csv.DictReader((HERE/'events.csv').open())}
    rows=[]
    for name in ('rr-1','rr-1_5','rr-2'):
        for r in csv.DictReader((HERE/name/'trades.csv').open()):
            if r['entry_price']:
                e=events[r['event_id']]
                raw=e['known_low' if r['direction']=='BUY' else 'known_high']
                rows.append((name,r,raw))
    code=r'''#include <algorithm>
#include <cmath>
#include <iostream>
#include <iomanip>
#define MathIsValidNumber std::isfinite
#define MathRound std::round
#define MathFloor std::floor
#define MathCeil std::ceil
#define MathAbs std::abs
#define MathMax std::max
#define MathMin std::min
double NormalizeDouble(double p,int digits){double f=std::pow(10,digits);return std::round(p*f)/f;}
#include "ScalpCore.mqh"
#include "EngulfPrice.hpp"
int main(){int buy;double entry,raw,rr;
std::cout<<std::setprecision(17);
while(std::cin>>buy>>entry>>raw>>rr){
EngulfBar b={raw,raw,raw,raw};
double sl=EngulfBufferedStop(buy,b,b,0,.01,.01,2);
double tp=ScalpSnap(entry+(buy?1:-1)*rr*std::abs(entry-sl),.01,2);
double bsl=ScalpBrokerPrice(buy,true,sl,.36,.01,2),btp=ScalpBrokerPrice(buy,true,tp,.36,.01,2);
double risk=buy?entry-bsl:bsl-entry, reward=buy?btp-entry:entry-btp;
bool valid=ScalpGeometry(buy,entry,sl,tp)&&ScalpGeometry(buy,entry,bsl,btp);
std::cout<<sl<<' '<<tp<<' '<<bsl<<' '<<btp<<' '<<risk<<' '<<(risk>0?reward/risk:0)<<' '<<valid<<'\n';
}}
'''
    with tempfile.TemporaryDirectory(prefix='wick-instant-price-verify-') as tmp:
        tmp=Path(tmp)
        # Cut before MT5 order-result enums; preserve actual stop functions.
        stop=(EA/'EngulfCore.mqh').read_text().split('// OrderSend acceptance')[0]+'\n#endif\n'
        (tmp/'EngulfPrice.hpp').write_text(stop)
        (tmp/'verify.cpp').write_text(code)
        subprocess.run(['clang++','-std=c++17','-O2','-I',str(EA),'-I',str(tmp),str(tmp/'verify.cpp'),'-o',str(tmp/'verify')],check=True)
        source=''.join(f"{int(r['direction']=='BUY')} {r['entry_price']} {raw} {r['rr']}\n" for _,r,raw in rows)
        outputs=subprocess.run([str(tmp/'verify')],input=source,text=True,capture_output=True,check=True).stdout.splitlines()
    assert len(outputs)==len(rows)
    fields=('strategy_sl','strategy_tp','stop_price','target_price','initial_risk','target_r_multiple')
    checks=0
    for (_,r,_),line in zip(rows,outputs):
        v=list(map(float,line.split()))
        for key,expected in zip(fields,v[:6]):
            assert math.isclose(float(r[key]),expected,abs_tol=1e-8,rel_tol=1e-10),(r['event_id'],r['rr'],key,r[key],expected)
            checks+=1
        assert bool(v[6])==(r['outcome']!='INVALID_STOP'),(r['event_id'],r['rr'],'geometry')
        checks+=1
    sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
    result={'rows_checked':len(rows),'price_and_geometry_checks_passed':checks,
            'method':'Actual ScalpCore.mqh + actual EngulfBufferedStop, compiled as C++ with std::round and NormalizeDouble shim; SL uses supplied M15 wick, zero buffer, tick/point .01. Price mapping only, no native EA broker execution.',
            'ea_source_sha256':{n:sha(EA/n) for n in ('ScalpCore.mqh','EngulfCore.mqh','InstantBroker.mqh')},
            'study_trades_sha256':{n:sha(HERE/n/'trades.csv') for n in ('rr-1','rr-1_5','rr-2')}}
    (HERE/'ea_mapping_verification.json').write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps(result,indent=2))


if __name__=='__main__':
    main()
