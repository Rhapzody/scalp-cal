/* Shared by the offline report and Node regression tests. No network dependencies. */
(function (root) {
'use strict';
function csv(text) {
  if (!text || !text.trim()) return [];
  const rows=[]; let row=[],cell='',quoted=false;
  for(let i=0;i<text.length;i++) {
    const ch=text[i];
    if(quoted) { if(ch==='"' && text[i+1]==='"'){cell+='"';i++;} else if(ch==='"')quoted=false; else cell+=ch; }
    else if(ch==='"')quoted=true;
    else if(ch===','){row.push(cell);cell='';}
    else if(ch==='\n'){row.push(cell.replace(/\r$/,''));if(row.some(v=>v!==''))rows.push(row);row=[];cell='';}
    else cell+=ch;
  }
  if(quoted)throw new Error('CSV มีช่องข้อความที่ไม่สมบูรณ์');
  if(cell!==''||row.length){row.push(cell.replace(/\r$/,''));rows.push(row);}
  if(!rows.length)return [];
  const header=rows.shift();
  return rows.map(r=>{if(r.length!==header.length)throw new Error('จำนวนคอลัมน์ CSV ไม่ตรง');return Object.fromEntries(header.map((k,i)=>[k,r[i]]));});
}
function latest(rows) {
  const byId=new Map();
  for(const d of rows) {
    if(!/^\d+$/.test(d.deal_ticket)||!/^\d+$/.test(d.revision))throw new Error('Deal identity ไม่ถูกต้อง');
    const key=[d.account_login,d.account_server,d.deal_ticket].join('|');
    if(!byId.has(key)||Number(byId.get(key).revision)<Number(d.revision))byId.set(key,d);
  }
  return [...byId.values()].filter(d=>d.action!=='DELETE').sort((a,b)=>Number(a.deal_time_msc)-Number(b.deal_time_msc)||a.deal_ticket.localeCompare(b.deal_ticket));
}
function encode(rows) {
  if(!rows.length)return "";const keys=Object.keys(rows[0]);const cell=s=>'"'+String(s??'').replace(/"/g,'""')+'"';
  return keys.join(',')+'\n'+rows.map(r=>keys.map(k=>cell(r[k])).join(',')).join('\n')+'\n';
}
function time(s) {
  // MT5 broker wall clock is deliberately kept on a synthetic UTC axis; no browser timezone conversion.
  if(!s)return NaN;
  return Date.parse(s.replace(/^(\d{4})\.(\d{2})\.(\d{2})/,'$1-$2-$3').replace(' ','T')+'Z')/1000;
}
function stamp(seconds) {return Number.isFinite(seconds)?new Date(seconds*1000).toISOString().slice(0,19).replace('T',' '):'—';}
function number(s) {return s===''||s==null?null:Number(s);}
function group(deals,positions=[]) {
  const observed=new Map(positions.map(p=>[p.id,p.open])); const map=new Map();
  for(const d of deals) {
    if(d.position_id==='0'||!d.position_id||!['DEAL_TYPE_BUY','DEAL_TYPE_SELL'].includes(d.deal_type))continue;
    let g=map.get(d.position_id);
    if(!g){g={id:d.position_id,symbol:d.symbol,currency:d.currency,deals:[],trades:[],net:0,first:Infinity,last:0,open:observed.has(d.position_id)?observed.get(d.position_id):null};map.set(g.id,g);}
    g.trades.push(d);g.first=Math.min(g.first,Number(d.deal_time_msc)/1000);g.last=Math.max(g.last,Number(d.deal_time_msc)/1000);
  }
  for(const d of deals){const g=map.get(d.position_id);if(g){g.deals.push(d);g.net+=Number(d.net)||0;}}
  return [...map.values()].sort((a,b)=>b.last-a.last);
}
function associate(groups,events) {
  const byId=new Map(groups.map(g=>[g.id,g])),deals=new Map(),orders=new Map(),tickets=new Map();
  function assign(map,key,id){if(!key||key==='0')return;if(map.has(key)&&map.get(key)!==id)map.set(key,null);else if(!map.has(key))map.set(key,id);}
  for(const g of groups){g.events=[];for(const d of g.deals){assign(deals,d.deal_ticket,g.id);assign(orders,d.order_ticket,g.id);}}
  for(const e of events)if(e.position_id&&e.position_id!=='0'&&byId.has(e.position_id))assign(tickets,e.position_ticket,e.position_id);
  const unlinked=[];
  for(const e of events){const id=(byId.has(e.position_id)?e.position_id:null)||deals.get(e.deal_ticket)||orders.get(e.order_ticket)||tickets.get(e.position_ticket);if(id&&byId.has(id))byId.get(id).events.push(e);else unlinked.push(e);}
  for(const g of groups)g.events.sort((a,b)=>time(a.observed_server_time)-time(b.observed_server_time)||a.session_id.localeCompare(b.session_id)||Number(a.sequence)-Number(b.sequence));
  return unlinked;
}
function levels(g) {
  const result=[];
  for(const d of g.trades)result.push({t:Number(d.deal_time_msc)/1000,sl:number(d.sl),tp:number(d.tp),source:'DEAL',order:0});
  for(const e of g.events||[]){
    if(e.event==='TRADE_TRANSACTION_POSITION'||(/^POSITION_/.test(e.event)&&e.origin==='OBSERVED_SNAPSHOT'))
      result.push({t:time(e.observed_server_time),sl:number(e.sl),tp:number(e.tp),source:e.origin,order:1});
  }
  return result.filter(p=>Number.isFinite(p.t)).sort((a,b)=>a.t-b.t||a.order-b.order);
}
function bars(chart) {
  if(!chart)return [];
  const seen=new Map();
  for(const b of chart.bars||[]) {
    if(b.length<9||!b.slice(0,5).every(Number.isFinite)||b[2]<Math.max(b[1],b[3],b[4])||b[3]>Math.min(b[1],b[2],b[4]))continue;
    seen.set(b[0],b);
  }
  return [...seen.values()].sort((a,b)=>a[0]-b[0]);
}
const api={csv,encode,latest,time,stamp,number,group,associate,levels,bars};
if(typeof module!=='undefined'&&module.exports)module.exports=api;
root.JournalModel=api;
})(globalThis);
