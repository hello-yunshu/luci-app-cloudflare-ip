'use strict';
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
String.prototype.format=function(...args){let i=0;return this.replace(/%s/g,()=>args[i++]);};
function E(tag,attrs={},children=[]){
 const node={tag,attrs,children:[],appendChild(child){this.children.push(child);return child;},removeChild(child){this.children.splice(this.children.indexOf(child),1);},get firstChild(){return this.children[0];}};
 for(const child of Array.isArray(children)?children:[children])node.appendChild(child);
 return node;
}
function text(node){return typeof node==='string'?node:!node?'':node.children.map(text).join(' ');}
function find(node,predicate){if(node&&typeof node==='object'){if(predicate(node))return node;for(const child of node.children){const result=find(child,predicate);if(result)return result;}}}
const source=fs.readFileSync(process.env.CFIP_TEST_OVERVIEW || path.join(__dirname,'../package/luci-app-cloudflare-ip/htdocs/luci-static/resources/view/cloudflare-ip/overview.js'),'utf8');
function makeView(status,response={success:true,tar:true}){
 const utils={callStatus:()=>Promise.resolve(status),loadSharedCSS(){},waitForServiceReady:()=>new Promise(()=>{}),appendFooter:x=>x,FOOTER_OPTIONS:{},setBusy(){},resetBusy(){}};
 return new Function('view','ui','rpc','uci','form','utils','E','_','setTimeout',source)(
  {extend:x=>x},{addNotification(){}},{declare:()=>()=>Promise.resolve(response)},{load:()=>Promise.resolve(),get:()=>undefined},{},utils,E,x=>x,()=>{});
}
function row(root,label){const found=find(root,node=>node.tag==='tr'&&node.children[0]&&node.children[0].tag==='th'&&text(node.children[0])===label);assert(found,label+' row missing');return text(found);}
(async()=>{
 for(const bad of [null,{},[],{success:false,error:'controlled status failure',running:false},{running:'false'}]){
  await assert.rejects(makeView(bad).load(),/Unable to load status:/);
 }
 const status={running:false,env:{}};
 assert.equal(await makeView(status).load(),status);
 let root=makeView(status).render(status);
 for(const label of ['tar','jq','PassWall','OpenClash','CFST']){
  assert.match(row(root,label),/Unknown/);assert.doesNotMatch(row(root,label),/Missing|Not Installed|Stopped/);
 }
 const malformed={running:false,env:{tar:'false',jq:null,passwall_installed:'false',openclash_installed:true,cfst_installed:'false'}};
 root=makeView(malformed).render(malformed);
 for(const label of ['tar','jq','PassWall','CFST'])assert.match(row(root,label),/Unknown/);
 assert.match(row(root,'OpenClash'),/Installed \(Status Unknown\)/);
 const known={running:false,env:{tar:true,jq:false,passwall_installed:true,passwall_running:false,openclash_installed:true,openclash_running:true,cfst_installed:false}};
 root=makeView(known).render(known);
 assert.match(row(root,'tar'),/Installed/);assert.match(row(root,'jq'),/Missing/);
 assert.match(row(root,'PassWall'),/Installed \(Stopped\)/);assert.match(row(root,'OpenClash'),/Running/);assert.match(row(root,'CFST'),/Not Installed/);
 const button=find(root,node=>node.tag==='button'&&text(node).includes('Refresh Environment'));
 await button.attrs.click.call(button);
 assert.match(row(root,'tar'),/Installed/);
 for(const label of ['jq','PassWall','OpenClash','CFST'])assert.match(row(root,label),/Unknown/);
 console.log('PASS actual Overview load rejects status failures; unknown observations remain unknown before and after refresh');
})().catch(error=>{console.error(error);process.exitCode=1;});
