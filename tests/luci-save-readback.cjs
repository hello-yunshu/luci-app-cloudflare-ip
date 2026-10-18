'use strict';
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
if (!String.prototype.format) Object.defineProperty(String.prototype,'format',{value:function(value){return this.replace('%s',value);},configurable:true});
const source=fs.readFileSync(process.env.CFIP_TEST_UTILS || path.join(__dirname,'../package/luci-app-cloudflare-ip/htdocs/luci-static/resources/cloudflare-ip/utils.js'),'utf8');
async function scenario({fresh,changes={},applyError=5,readError,enabled='0'}) {
 const staged={main:{'.name':'main','.type':'service',enabled:enabled,mode:'passwall'},custom:{'.name':'custom','.type':'source',url:'https://example.invalid/custom',enabled:'1'}};
 const calls={get:0,changes:0,restart:0,reload:0,notifications:[]};
 const uci={get:(c,s,k)=>staged[s]&&staged[s][k],sections:()=>Object.values(staged),load:()=>Promise.resolve(),
  changes:()=>{calls.changes++;return Promise.resolve(changes);},apply:()=>applyError?Promise.reject(applyError):Promise.resolve()};
 const rpc={declare:def=>()=>{
  if(def.object==='uci' && def.method==='get'){calls.get++;return readError?Promise.reject(readError):Promise.resolve(fresh);}
  if(def.method==='status')return Promise.resolve({running:true,last_result:'success'});
  if(def.method==='restart')calls.restart++;
  return Promise.resolve({success:true});
 }};
 const ui={addNotification:(unused,node,type)=>calls.notifications.push({node,type})};
 const utils=new Function('uci','rpc','ui','dom','baseclass','_','window','E',source)(uci,rpc,ui,{}, {extend:v=>v},v=>v,
  {setTimeout:()=>{calls.reload++;return 1;},clearTimeout:()=>{}},(tag,text)=>text);
 const view={handleSave:()=>Promise.resolve()};utils.createHandleSaveApply(view);
 await view.handleSaveApply();return calls;
}
(async()=>{
 const base={main:{'.name':'main','.type':'service',enabled:'0',mode:'passwall'},custom:{'.name':'custom','.type':'source',url:'https://example.invalid/custom',enabled:'1'}};
 const changed=structuredClone(base);changed.main.enabled='1';
 let result=await scenario({fresh:changed});
 assert(result.notifications.some(n=>n.type==='error'),'stale cache must not report successful commit');
 assert.equal(result.restart,0);assert.equal(result.reload,0);assert.equal(result.get,1);
 result=await scenario({fresh:base});assert(result.notifications.some(n=>n.type==='info'));assert.equal(result.get,1);assert(result.changes>0);
 const custom=structuredClone(base);custom.custom.url='https://example.invalid/other';
 result=await scenario({fresh:custom});assert(result.notifications.some(n=>n.type==='error'));assert.equal(result.reload,0);
 result=await scenario({fresh:base,changes:{cf_ip:[['set','main','enabled','0']]}});assert(result.notifications.some(n=>n.type==='error'));assert.equal(result.reload,0);
 result=await scenario({fresh:base,readError:new Error('read failed')});assert(result.notifications.some(n=>n.type==='error'));assert.equal(result.reload,0);
 for (const fresh of [null,{}, {main:base.main}]) {
  result=await scenario({fresh});assert(result.notifications.some(n=>n.type==='error'));assert.equal(result.restart,0);
 }
 result=await scenario({fresh:base,changes:{cf_ip:{}}});assert(result.notifications.some(n=>n.type==='error'));
 result=await scenario({fresh:base,changes:{unrelated:[['set','x','y','z']]}});assert(result.notifications.some(n=>n.type==='info'));
 const enabled=structuredClone(base);enabled.main.enabled='1';
 result=await scenario({fresh:enabled,enabled:'1',applyError:null});assert.equal(result.restart,1);assert(result.notifications.some(n=>String(n.node).includes('service is ready')));
 console.log('PASS actual LuCI save handler rejects cached/uncommitted/mismatched readback; matching fresh code-5 readback accepted (module harness)');
})().catch(error=>{console.error(error);process.exitCode=1;});
