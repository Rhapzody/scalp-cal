'use strict';
const assert=require('node:assert/strict');
const M=require('../../MQL5/Scripts/TradeJournal/ReportModel.js');
let checks=0;function check(fn){fn();checks++;}
const base={account_login:'123456789012345678',account_server:'Broker-Demo',deal_ticket:'18446744073709551615',revision:'1',action:'UPSERT',position_id:'9007199254740993',deal_time_msc:'1760000000000',deal_type:'DEAL_TYPE_BUY',entry:'DEAL_ENTRY_IN',symbol:'XAUUSD',currency:'USD',order_ticket:'9007199254740999',price:'3000',sl:'2990',tp:'3010',volume:'0.2',profit:'0',commission:'-1',swap:'0',fee:'0',net:'-1',comment:'test,"quotes"\nไทย </script>'};
check(()=>assert.deepEqual(M.csv(M.encode([base])),[base]));
check(()=>assert.equal(M.csv(M.encode([base]))[0].deal_ticket,'18446744073709551615'));
const update={...base,revision:'2',net:'-2',commission:'-2'};
check(()=>assert.deepEqual(M.latest([update,base]),[update]));
check(()=>assert.deepEqual(M.latest([base,{...update,action:'DELETE'}]),[]));
check(()=>assert.throws(()=>M.csv('a,b\n"unterminated')));
const exit={...base,deal_ticket:'2',order_ticket:'222',entry:'DEAL_ENTRY_OUT',deal_type:'DEAL_TYPE_SELL',deal_time_msc:'1760000060000',profit:'10',net:'9',volume:'.1'};
const final={...exit,deal_ticket:'3',deal_time_msc:'1760000120000',profit:'4',net:'3'};
const charge={...base,deal_ticket:'4',deal_type:'DEAL_TYPE_COMMISSION',net:'-3',commission:'0',profit:'-3',deal_time_msc:'1760000180000',order_ticket:'0'};
const unallocated={...charge,deal_ticket:'5',position_id:'0',net:'-100'};
const groups=M.group([base,exit,final,charge,unallocated],[{id:base.position_id,open:false}]);
check(()=>assert.equal(groups.length,1));check(()=>assert.equal(groups[0].net,8));check(()=>assert.equal(groups[0].trades.length,3));check(()=>assert.equal(groups[0].deals.length,4));check(()=>assert.equal(groups[0].last,1760000120));check(()=>assert.equal(groups[0].open,false));
const snapshot={event:'POSITION_BASELINE',origin:'OBSERVED_SNAPSHOT',position_id:base.position_id,position_ticket:'777',observed_server_time:'2025.10.09 08:53:20',session_id:'s1',sequence:'1',sl:'2990',tp:'3010'};
const edit={event:'TRADE_TRANSACTION_POSITION',origin:'LIVE_TRANSACTION',position_id:'',position_ticket:'777',observed_server_time:'2025.10.09 08:54:00',session_id:'s1',sequence:'2',sl:'2995',tp:'3010'};
const unlinked={...edit,position_ticket:'888'};
check(()=>assert.deepEqual(M.associate(groups,[edit,snapshot,unlinked]),[unlinked]));
check(()=>assert.equal(groups[0].events.length,2));
check(()=>assert.ok(M.levels(groups[0]).some(l=>l.sl===2995&&l.source==='LIVE_TRANSACTION')));
check(()=>assert.equal(M.levels(groups[0]).filter(l=>l.source==='DEAL').length,3));
check(()=>assert.equal(M.time('2025.10.09 08:53:20'),Date.UTC(2025,9,9,8,53,20)/1000));
check(()=>assert.equal(M.stamp(M.time('2025.10.09 08:53:20')),'2025-10-09 08:53:20'));
const candle=[10,100,110,90,105,5,0,20,true];
check(()=>assert.deepEqual(M.bars({bars:[candle,candle,[20,100,95,90,110,0,0,0,true]]}),[candle]));
check(()=>assert.deepEqual(M.bars(null),[]));
// Unknown ticket is not assumed to be a stable position ID.
check(()=>assert.deepEqual(M.associate(groups,[{...edit,position_ticket:base.position_id}]),[{...edit,position_ticket:base.position_id}]));
// Close by and netting reversal remain distinct executions within the broker position.
const reversal={...exit,entry:'DEAL_ENTRY_INOUT'};check(()=>assert.equal(M.group([base,reversal])[0].trades[1].entry,'DEAL_ENTRY_INOUT'));
console.log('Journal report model: '+checks+' checks passed.');
