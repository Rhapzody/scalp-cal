'use strict';
// DOM unit harness, not a substitute for browser rendering or native file-download QA.
const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict'),path=require('node:path');
const source=path.resolve(__dirname,'../../MQL5/Scripts/TradeJournal');
const N=require(source+'/NotesModel.js'),M=require(source+'/ReportModel.js');
const html=fs.readFileSync(source+'/Report.html','utf8');
let checks=0;function check(fn){fn();checks++;}
class El{
 constructor(tag='div'){this.tag=tag;this.children=[];this.value='';this.hidden=false;this.listeners={};this.attributes={};this.textContent='';this.checked=false;}
 appendChild(e){this.children.push(e);e.parent=this;return e;}append(...els){els.forEach(e=>this.appendChild(e));}replaceChildren(...els){this.children=[];this.append(...els);}remove(){this.parent.children=this.parent.children.filter(e=>e!==this);}setAttribute(k,v){this.attributes[k]=v;}addEventListener(k,fn){this.listeners[k]=fn;}focus(){this.focused=true;}click(){this.onclick?.();}
 querySelector(selector){return this.children.find(e=>selector==='input[type=text]'?e.tag==='input'&&e.type==='text':selector==='input[type=checkbox]'?e.tag==='input'&&e.type==='checkbox':false);}get lastChild(){return this.children.at(-1);}
}
function memory(){const m=new Map();return {getItem:k=>m.get(k)??null,setItem:(k,v)=>m.set(k,v)};}
const groups=[0,1].map(n=>({id:'900719925474099'+(3+n),symbol:'XAUUSD',net:n?-12.5:8.2,currency:'USD',first:1789044000+n*3600,trades:[{account_login:'1234567',account_server:'DEMO • Synthetic data'}]}));
function page(storage=memory(),notes){const elements=new Map([...html.matchAll(/id="([^"]+)"/g)].map(m=>[m[1],new El()]));const $=id=>{assert.ok(elements.has(id),'Missing HTML element '+id);return elements.get(id);};const names=[...html.matchAll(/name="([^"]+)"/g)].map(m=>m[1]),fields=new Map(N.fields.map(f=>{assert.ok(names.includes(f),'Missing form field '+f);return [f,new El()];}));$('noteForm').elements={namedItem:n=>fields.get(n)};const downloads=[],events={},context={JournalNotes:N,JournalModel:M,document:{getElementById:$,createElement:t=>new El(t)},window:{localStorage:storage,addEventListener:(n,fn)=>events[n]=fn},location:{hash:''},Date,Set};vm.runInNewContext(fs.readFileSync(source+'/ReportNotebook.js','utf8'),context);let selected;const app=context.JournalNotebook.create({data:{demo:true,notes},groups,select:g=>{selected=g;app.open(g);},download:(content,name,type)=>downloads.push({content,name,type})});return {$,app,fields,downloads,events,storage,select:g=>app.open(g),input:(field,value)=>{fields.get(field).value=value;$('noteForm').listeners.input();},selected:()=>selected};}
(async()=>{
let p=page();check(()=>assert.equal(p.$('journalRows').children.length,2));
p.$('journalRows').children[0].children[7].children[0].click();check(()=>assert.equal(p.selected().id,groups[0].id));check(()=>assert.equal(p.$('overview').hidden,true));check(()=>assert.equal(p.$('detail').hidden,false));
p.input('setup','My pullback');p.input('before','ไทย\n</script><script>alert(1)</script>');p.input('status','reviewed');
check(()=>assert.equal(p.app.notes(groups[0]).records[0].fields.setup,'My pullback'));check(()=>assert.equal(p.$('journalRows').children[0].children[5].textContent,'รีวิวแล้ว'));
p.$('addCheck').click();const row=p.$('checklist').lastChild;row.querySelector('input[type=text]').value='เงื่อนไขของฉัน';row.querySelector('input[type=checkbox]').checked=true;p.$('noteForm').listeners.input();check(()=>assert.equal(p.app.notes(groups[0]).records[0].checklist.at(-1).checked,true));row.children[2].click();check(()=>assert.equal(p.app.notes(groups[0]).records[0].checklist.length,4));
p.select(groups[1]);check(()=>assert.equal(p.fields.get('setup').value,''));p.input('setup','Second');p.select(groups[0]);check(()=>assert.equal(p.fields.get('setup').value,'My pullback'));
p.$('backList').click();check(()=>assert.equal(p.$('detail').hidden,true));p.$('reviewFilter').value='reviewed';p.$('reviewFilter').onchange();check(()=>assert.equal(p.$('journalRows').children.length,1));p.$('listSearch').value='does not exist';p.$('listSearch').oninput();check(()=>assert.equal(p.$('journalRows').children[0].children[0].colSpan,8));
p.$('backupNotes').click();const backup=p.downloads.at(-1);check(()=>assert.equal(N.parseBundle(backup.content).length,2));check(()=>assert.ok(backup.name.endsWith('.json')));
const restored=page(p.storage);restored.select(groups[0]);check(()=>assert.equal(restored.fields.get('before').value,'ไทย\n</script><script>alert(1)</script>'));
const embedded=page(memory(),p.app.notes());embedded.select(groups[0]);check(()=>assert.equal(embedded.fields.get('setup').value,'My pullback'));
async function importFile(p,content){await p.$('importNotes').onchange({target:{files:[{size:content.length,text:async()=>content}],value:'file'}});}
const target=page();await importFile(target,backup.content);check(()=>assert.equal(target.$('importPreview').hidden,false));check(()=>assert.equal(target.$('replaceNotes').checked,false));target.$('applyImport').click();target.select(groups[0]);check(()=>assert.equal(target.fields.get('setup').value,'My pullback'));
target.input('setup','Keep my edit');await importFile(target,backup.content);target.$('applyImport').click();check(()=>assert.equal(target.fields.get('setup').value,'Keep my edit'));
await importFile(target,backup.content);target.$('replaceNotes').checked=true;target.$('applyImport').click();check(()=>assert.equal(target.fields.get('setup').value,'My pullback'));
const wrong=N.parseBundle(backup.content).map(r=>({...r,identity:{...r.identity,account:'999'}}));await importFile(target,JSON.stringify(N.bundle(wrong)));check(()=>assert.equal(target.$('applyImport').disabled,true));
await importFile(target,'{"invalid":true}');check(()=>assert.match(target.$('transferStatus').textContent,/นำเข้าไม่ได้/));check(()=>assert.equal(target.$('importPreview').hidden,true));
const blocked=page({getItem:()=>null,setItem:()=>{throw Error('quota exceeded');}});blocked.select(groups[0]);blocked.input('before','Must preserve draft');check(()=>assert.equal(blocked.$('draftWarning').hidden,false));blocked.select(groups[1]);blocked.select(groups[0]);check(()=>assert.equal(blocked.fields.get('before').value,'Must preserve draft'));blocked.$('backupNotes').click();check(()=>assert.equal(N.parseBundle(blocked.downloads[0].content)[0].fields.before,'Must preserve draft'));let prevented=false;blocked.events.beforeunload({preventDefault:()=>prevented=true});check(()=>assert.equal(prevented,true));
const shared=memory(),first=page(shared),second=page(shared);first.select(groups[0]);second.select(groups[0]);first.input('before','first tab');second.input('before','second tab');check(()=>assert.equal(second.$('draftWarning').hidden,false));check(()=>assert.equal(second.app.notes(groups[0]).records[0].fields.before,'second tab'));check(()=>assert.equal(page(shared).app.notes(groups[0]).records[0].fields.before,'first tab'));
console.log('Journal notebook DOM units: '+checks+' checks passed.');
})().catch(e=>{console.error(e);process.exitCode=1;});
