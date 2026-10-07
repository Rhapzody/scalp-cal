'use strict';
const assert=require('node:assert/strict'),N=require('../../MQL5/Scripts/TradeJournal/NotesModel.js');
let checks=0;function check(fn){fn();checks++;}
function storage(){const map=new Map();return {getItem:k=>map.get(k)??null,setItem:(k,v)=>map.set(k,v),map};}
const i=N.identity('1234567','Broker • ไทย','9007199254740993',false),mem=storage();let s=N.create(mem);
check(()=>assert.equal(s.get(i).fields.status,'todo'));
check(()=>assert.equal(s.records([i]).length,0));
const b=s.get(i),fields={...b.fields,setup:'Pullback',before:'เหตุผล\n"quotes" </script><script>alert(1)</script>',moodBefore:'สงบ',status:'reviewing'};
let result=s.save(i,fields,[{label:'เช็ค <script> & "ข่าว"',checked:true}]);
check(()=>assert.equal(result.saved,true));check(()=>assert.equal(s.dirty(),false));
s=N.create(mem);check(()=>assert.equal(s.get(i).fields.before,fields.before));check(()=>assert.equal(s.get(i).checklist[0].checked,true));
check(()=>assert.equal(s.get({...i,account:'7654321'}).updatedAt,''));check(()=>assert.equal(s.get({...i,server:'Broker 2'}).updatedAt,''));check(()=>assert.equal(s.get({...i,demo:true}).updatedAt,''));check(()=>assert.equal(s.get({...i,position:'9007199254740992'}).updatedAt,''));
check(()=>assert.notEqual(N.key({...i,server:'a:b'}),N.key({...i,server:'a',position:'2'})));
const portable=N.bundle(s.records([i]));check(()=>assert.deepEqual(N.parseBundle(JSON.stringify(portable)),portable.records));
const fresh=N.create(storage(),N.parseBundle(portable));check(()=>assert.equal(fresh.get(i).fields.setup,'Pullback'));
const imported=N.create(storage());check(()=>assert.deepEqual(imported.importRecords(portable.records),{added:1,skipped:0,failed:0}));check(()=>assert.equal(imported.get(i).fields.before,fields.before));
const changed={...portable.records[0],fields:{...fields,setup:'Different'}};
check(()=>assert.deepEqual(imported.importRecords([changed]),{added:0,skipped:1,failed:0}));check(()=>assert.equal(imported.get(i).fields.setup,'Pullback'));
check(()=>assert.deepEqual(imported.importRecords([changed],true),{added:1,skipped:0,failed:0}));check(()=>assert.equal(imported.get(i).fields.setup,'Different'));
check(()=>assert.throws(()=>N.parseBundle({...portable,version:2})));
check(()=>assert.throws(()=>N.parseBundle({...portable,records:[changed,changed]})));
check(()=>assert.throws(()=>N.parseBundle({...portable,records:[{...changed,identity:{...i,position:9007199254740993}}]})));
check(()=>assert.throws(()=>N.normalize({...changed,updatedAt:'tomorrow'})));
check(()=>assert.throws(()=>N.normalize({...changed,fields:{...fields,status:'fake'}})));
check(()=>assert.throws(()=>N.normalize({...changed,fields:{...fields,before:'x'.repeat(30001)}})));
check(()=>assert.throws(()=>N.normalize({...changed,checklist:[{label:'a',checked:1}]})));
check(()=>assert.throws(()=>N.normalize({...changed,checklist:Array(101).fill({label:'a',checked:false})})));
const unavailable=N.create(null);result=unavailable.save(i,fields,[]);check(()=>assert.equal(result.saved,false));check(()=>assert.equal(unavailable.dirty(),true));check(()=>assert.equal(unavailable.records([i])[0].fields.before,fields.before));
const full=N.create({getItem:()=>null,setItem:()=>{throw Error('quota');}});check(()=>assert.equal(full.save(i,fields,[]).saved,false));check(()=>assert.equal(full.records([i]).length,1));
const corrupt=storage();corrupt.setItem(N.prefix+N.key(i),'bad json');const bad=N.create(corrupt);check(()=>assert.equal(bad.save(i,fields,[]).saved,false));check(()=>assert.equal(corrupt.getItem(N.prefix+N.key(i)),'bad json'));
const shared=storage(),a=N.create(shared),c=N.create(shared);a.get(i);c.get(i);a.save(i,fields,[]);check(()=>assert.equal(c.save(i,{...fields,setup:'other tab'},[]).saved,false));check(()=>assert.equal(N.create(shared).get(i).fields.setup,'Pullback'));check(()=>assert.equal(c.records([i])[0].fields.setup,'other tab'));
const older={...changed,updatedAt:'2000-01-01T00:00:00.000Z'};check(()=>assert.equal(N.create(mem,[older]).get(i).fields.setup,'Pullback'));
const newer={...changed,updatedAt:'2099-01-01T00:00:00.000Z'};check(()=>assert.equal(N.create(mem,[newer]).get(i).fields.setup,'Different'));
const extra=N.identity(i.account,i.server,'9007199254740994',false);s.save(extra,{...fields,setup:'second position'},[]);check(()=>assert.equal(s.records([i]).length,1));check(()=>assert.equal(s.records([extra])[0].identity.position,extra.position));
check(()=>assert.throws(()=>N.parseBundle('x'.repeat(10000001))));
// Reject whole malformed import before mutating any notes.
const atomic=N.create(storage());check(()=>assert.throws(()=>atomic.importRecords([changed,{...changed,updatedAt:'bad'}])));check(()=>assert.equal(atomic.records([i]).length,0));
console.log('Journal personal notes: '+checks+' checks passed.');
