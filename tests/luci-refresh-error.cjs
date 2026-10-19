'use strict';
// Execute the actual refresh click handler with an isolated DOM/RPC fixture.
const fs=require('node:fs');
const path=require('node:path');
const assert=require('node:assert/strict');
String.prototype.format=function(...args){let i=0;return this.replace(/%s/g,()=>args[i++]);};
function E(tag,attrs={},children=[]){
 const n={tag,attrs,children:[],appendChild(c){this.children.push(c);if(c&&typeof c==='object')c.parentNode=this;return c;},removeChild(c){this.children.splice(this.children.indexOf(c),1);return c;},replaceChild(c,old){this.children[this.children.indexOf(old)]=c;c.parentNode=this;},get firstChild(){return this.children[0];}};
 for(const c of Array.isArray(children)?children:[children])n.appendChild(c);
 return n;
}
function flatten(n){return typeof n==='string'?n:!n?'':(n.attrs.class||'')+' '+n.children.map(flatten).join(' ');}
function find(n,p){if(n&&typeof n==='object'){if(p(n))return n;for(const c of n.children){const result=find(c,p);if(result)return result;}}}
const source=fs.readFileSync(path.join(__dirname,'../package/luci-app-cloudflare-ip/htdocs/luci-static/resources/view/cloudflare-ip/overview.js'),'utf8');
(async()=>{
 for(const response of [{success:false,error:'controlled refresh failure'},{success:false},null,{success:true,tar:true,jq:true}]){
  const notices=[];let busy=0,reset=0;
  const utils={loadSharedCSS(){},waitForServiceReady:()=>new Promise(()=>{}),appendFooter:x=>x,FOOTER_OPTIONS:{},setBusy(){busy++;},resetBusy(){reset++;}};
  const view=new Function('view','ui','rpc','uci','form','utils','E','_','setTimeout',source)({extend:x=>x},{addNotification:(a,b,c)=>notices.push({text:flatten(b),kind:c})},{declare:()=>()=>Promise.resolve(response)},{get:()=>undefined},{},utils,E,x=>x,()=>{});
  const root=view.render({running:false,env:{tar:true,jq:true}});
  const button=find(root,n=>n.tag==='button'&&flatten(n).includes('Refresh Environment'));
  assert.ok(button);
  const before=flatten(root);
  await button.attrs.click.call(button);
  assert.equal(busy,1);assert.equal(reset,1);assert.equal(notices.length,1);
  if(response&&response.success===true)assert.equal(notices[0].kind,'info');
  else{assert.equal(notices[0].kind,'error');assert.equal(flatten(root),before,'failure replaced last known environment badges');}
 }
 console.log('PASS actual refresh handler rejects failed/missing results, preserves badges and resets busy; successful refresh still works');
})().catch(e=>{console.error(e);process.exitCode=1;});
