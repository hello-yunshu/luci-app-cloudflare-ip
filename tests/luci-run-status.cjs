'use strict';
// Actual Overview click handler + utils polling, isolated DOM/RPC; not browser proof.
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
String.prototype.format=function(...args){let i=0;return this.replace(/%s/g,()=>args[i++]);};
function E(tag,attrs={},children=[]){return {tag,attrs,children:Array.isArray(children)?children:[children],isConnected:true,appendChild(c){this.children.push(c);return c;},getAttribute(k){return this.attrs[k]??null;},setAttribute(k,v){this.attrs[k]=v;},removeAttribute(k){delete this.attrs[k];},get textContent(){return this.children.map(c=>typeof c==='string'?c:c.textContent||'').join('');},set textContent(v){this.children=[v];}};}
function find(n,p){if(n&&typeof n==='object'){if(p(n))return n;for(const c of n.children||[]){const r=find(c,p);if(r)return r;}}}
const base=path.join(__dirname,'../package/luci-app-cloudflare-ip/htdocs/luci-static/resources');
const utilsSource=fs.readFileSync(path.join(base,'cloudflare-ip/utils.js'),'utf8');
const viewSource=fs.readFileSync(path.join(base,'view/cloudflare-ip/overview.js'),'utf8');
(async()=>{
 const cases=[];
 const ack={success:true,accepted:true,acknowledged:true,running:true,runId:'new-run',requestId:'new-request'};
 for(const scenario of ['old then matching active','matching early failure','old cache only','wrong request','unconfirmed startup','navigation cancellation','network failure','hanging status','incomplete acknowledgement','matching completed task']){
  let polls=0,reloads=0;const notices=[];
  const utils=new Function('uci','rpc','ui','dom','baseclass','_','window',utilsSource)({}, {declare:()=>()=>Promise.resolve({})},{},{},{extend:x=>x},x=>x,{setTimeout,clearTimeout});
  utils.loadSharedCSS=()=>{};utils.appendFooter=x=>x;utils.reloadSoon=()=>{reloads++;};
  const realWait=utils.waitForRunStatus;
  if(realWait)utils.waitForRunStatus=(fetch,a,o)=>realWait(fetch,a,Object.assign({},o,{interval:2,timeout:30}));
  utils.callStatus=()=>{
   polls++;
   if(scenario==='hanging status')return new Promise(()=>{});
   if(scenario==='matching completed task')return Promise.resolve({runId:ack.runId,requestId:ack.requestId,last_result:'success',active_run:false});
   if(scenario==='network failure')return Promise.reject(new Error('controlled network failure'));
   if(scenario==='matching early failure')return Promise.resolve({runId:ack.runId,requestId:ack.requestId,last_result:'failed',active_run:false,error:'context failed'});
   if(scenario==='wrong request')return Promise.resolve({runId:ack.runId,requestId:'foreign',last_result:'success'});
   if(scenario==='old then matching active'&&polls>1)return Promise.resolve({runId:ack.runId,requestId:ack.requestId,active_run:true,last_result:'running'});
   return Promise.resolve({runId:'previous-run',requestId:'previous-request',last_result:'success',running:true});
  };
  const response=scenario==='incomplete acknowledgement'?{success:true,accepted:true,acknowledged:true}:scenario==='unconfirmed startup'?{success:false,accepted:null,unconfirmed:true,error:'startup unconfirmed'}:ack;
  const view=new Function('view','ui','rpc','uci','form','utils','E','_','setTimeout',viewSource)({extend:x=>x},{addNotification:(a,n,k)=>notices.push({text:n.textContent,kind:k})},{declare:()=>()=>Promise.resolve(response)},{get:()=>undefined},{},utils,E,x=>x,()=>{});
  const root=view.render({running:true,last_result:'success'});
  const button=find(root,n=>n.tag==='button'&&n.textContent.includes('Run Speed Test'));assert.ok(button);
  const pending=button.attrs.click.call(button);
  if(scenario==='navigation cancellation')root.isConnected=false;
  await pending;await new Promise(r=>setTimeout(r,45));
  if(scenario==='old then matching active'||scenario==='matching early failure'||scenario==='matching completed task'){
   assert.equal(reloads,1,scenario+': matching task status was not observed');
   if(scenario==='old then matching active')assert.ok(polls>=2,'reloaded without matching task identity');
  }else{assert.equal(reloads,0,scenario+': reloaded without matching task status');if(scenario!=='navigation cancellation')assert.ok(notices.some(n=>n.kind==='error'),scenario+': missing error');assert.equal(button.disabled,false,scenario+': button stayed busy');}
  const ended=polls;await new Promise(r=>setTimeout(r,8));assert.equal(polls,ended,'polling continued after settlement');
  cases.push(scenario);
 }
 console.log(JSON.stringify({status:'PASS',scope:'actual Overview handler and utils with DOM/RPC fixtures',cases},null,2));
})().catch(e=>{console.error(e);process.exitCode=1;});
