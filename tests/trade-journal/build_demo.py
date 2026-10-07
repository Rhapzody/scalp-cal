"""Deterministic synthetic report for browser QA. Contains no account data."""
import csv, io, json, math, re
from datetime import datetime, timezone
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
source=(ROOT/'MQL5/Experts/TradeJournal/TradeJournal.mq5').read_text()
headers={name:re.search(r'const string '+name+r'="([^"]+)"',source)[1].split(',') for name in ['DEAL_HEADER','EVENT_HEADER','SESSION_HEADER']}
start=int(datetime(2026,9,10,tzinfo=timezone.utc).timestamp())
def stamp(t): return datetime.fromtimestamp(t,timezone.utc).strftime('%Y.%m.%d %H:%M:%S')
def csv_text(name,rows):
    s=io.StringIO(); w=csv.DictWriter(s,fieldnames=headers[name],lineterminator='\n');w.writeheader();w.writerows(rows);return s.getvalue()
bars=[]
for i in range(3000):
    o=3644+.012*i+1.1*math.sin(i/25)+.25*math.sin(i/4)
    c=3644+.012*(i+1)+1.1*math.sin((i+1)/25)+.25*math.sin((i+1)/4)
    bars.append([start+i*60,round(o,3),round(max(o,c)+.12+.09*abs(math.sin(i)),3),round(min(o,c)-.1-.07*abs(math.cos(i)),3),round(c,3),70+i%57,0,20,True])
deals=[];events=[];positions=[];charts=[]
def add_deal(ticket,pid,idx,kind,entry,vol,price,sl,tp,profit=0,reason='EXPERT'):
    row=dict.fromkeys(headers['DEAL_HEADER'],'');row.update(schema_version='1',recorded_server_time=stamp(start+3000*60),session_id='DEMO',action='UPSERT',revision='1',origin='DEMO',account_login='1234567',account_server='DEMO • Synthetic data',currency='USD',deal_ticket=str(ticket),order_ticket=str(ticket+1000),position_id=pid,deal_time_msc=str((start+idx*60+25)*1000),deal_time=stamp(start+idx*60+25),deal_type='DEAL_TYPE_'+kind,entry='DEAL_ENTRY_'+entry,reason='DEAL_REASON_'+reason,magic='26091201',symbol='XAUUSD',volume=str(vol),price=str(price),sl=str(sl),tp=str(tp),profit=f'{profit:.2f}',commission='-0.35',swap='0',fee='0',net=f'{profit-.35:.2f}',comment='DEMO ONLY',external_id='');deals.append(row)
def add_event(pid,ticket,idx,sl,tp,vol,event='TRADE_TRANSACTION_POSITION',origin='LIVE_TRANSACTION'):
    row=dict.fromkeys(headers['EVENT_HEADER'],'');row.update(schema_version='1',observed_server_time=stamp(start+idx*60+26),observed_local_time=stamp(start+idx*60+26),session_id='DEMO',sequence=str(len(events)+1),origin=origin,event=event,account_login='1234567',account_server='DEMO • Synthetic data',currency='USD',symbol='XAUUSD',position_ticket=str(ticket),position_id=pid if origin=='OBSERVED_SNAPSHOT' else '',deal_or_position_type='POSITION_TYPE_BUY',volume=str(vol),price=str(bars[idx][4]),sl=str(sl),tp=str(tp),magic='26091201' if origin=='OBSERVED_SNAPSHOT' else '');events.append(row)
for p,(first,last,buy) in enumerate([(2200,2225,True),(2250,2270,False)]):
    pid=str(9007199254740993+p);ticket=710000+p;entry=bars[first][4];sl=entry+(-1.6 if buy else 1.6);tp=entry+(1.6 if buy else -1.6)
    add_deal(100+p*10,pid,first,'BUY' if buy else 'SELL','IN',.2,entry,sl,tp)
    add_event(pid,ticket,first,sl,tp,.2,'POSITION_FIRST_OBSERVED','OBSERVED_SNAPSHOT')
    if buy:
        add_event(pid,ticket,first+8,entry-.3,tp,.2)
        partial=bars[first+12][4];add_deal(101,pid,first+12,'SELL','OUT',.1,partial,entry-.3,tp,(partial-entry)*10,'CLIENT')
        add_event(pid,ticket,first+12,entry-.3,tp,.1,'POSITION_CHANGED','OBSERVED_SNAPSHOT')
    exit=bars[last][4];volume=.1 if buy else .2
    add_deal(102+p*10,pid,last,'SELL' if buy else 'BUY','OUT',volume,exit,entry-.3 if buy else sl,tp,(exit-entry)*volume*100*(1 if buy else -1),'CLIENT')
    add_event(pid,ticket,last,entry-.3 if buy else sl,tp,volume,'POSITION_NO_LONGER_OPEN','LAST_OBSERVED_SNAPSHOT')
    positions.append({'id':pid,'open':False})
    for tf,k in [('M1',1),('M5',5),('M15',15)]:
        aggregated=[]
        for i in range(0,len(bars),k):
            chunk=bars[i:i+k];aggregated.append([chunk[0][0],chunk[0][1],max(b[2] for b in chunk),min(b[3] for b in chunk),chunk[-1][4],sum(b[5] for b in chunk),0,20,True])
        selected=aggregated[max(0,first//k-100):last//k+31]
        charts.append({'positionId':pid,'timeframe':tf,'seconds':k*60,'status':'ready','afterAvailable':30,'collectedAt':start+3000*60,'bars':selected})
sessions=[]
for i,event in [(0,'START'),(2180,'CONNECTED'),(2200,'HEARTBEAT'),(2280,'STOP')]:
    r=dict.fromkeys(headers['SESSION_HEADER'],'');r.update(schema_version='1',server_time=stamp(start+i*60),local_time=stamp(start+i*60),session_id='DEMO',account_login='1234567',account_server='DEMO • Synthetic data',event=event,detail='Synthetic example only');sessions.append(r)
data=dict(version='1.20',generatedAt=start+3000*60,demo=True,before=100,after=30,positionsWithCharts=2,dealsCsv=csv_text('DEAL_HEADER',deals),eventsCsv=csv_text('EVENT_HEADER',events),sessionsCsv=csv_text('SESSION_HEADER',sessions),positions=positions,charts=charts)
folder=ROOT/'MQL5/Scripts/TradeJournal'
html=(folder/'Report.html').read_text().replace('__JOURNAL_MODEL__',(folder/'ReportModel.js').read_text()).replace('__JOURNAL_NOTES__',(folder/'NotesModel.js').read_text()).replace('__JOURNAL_NOTEBOOK__',(folder/'ReportNotebook.js').read_text()).replace('__JOURNAL_UI__',(folder/'ReportUI.js').read_text()).replace('__JOURNAL_DATA__',json.dumps(data,ensure_ascii=False).replace('<','\\u003c'))
output=ROOT/'docs/experts/trade-journal/journal-demo.html';output.write_text(html)
print(output)
