'use strict';
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
String.prototype.format=function(...args){let i=0;return this.replace(/%s/g,()=>args[i++]);};
function E(tag,attrs={},children=[]){
 const node={tag,attrs,children:[],appendChild(child){this.children.push(child);if(child&&typeof child==='object')child.parentNode=this;return child;},insertBefore(child,reference){const index=reference==null?this.children.length:this.children.indexOf(reference);this.children.splice(index<0?this.children.length:index,0,child);if(child&&typeof child==='object')child.parentNode=this;return child;},replaceChild(child,previous){const index=this.children.indexOf(previous);this.children[index]=child;if(child&&typeof child==='object')child.parentNode=this;return previous;},removeChild(child){this.children.splice(this.children.indexOf(child),1);},get childNodes(){return this.children;},get firstChild(){return this.children[0];}};
 for(const child of Array.isArray(children)?children:[children])node.appendChild(child);
 return node;
}
function text(node){return typeof node==='string'?node:!node?'':node.children.map(text).join(' ');}
function find(node,predicate){if(node&&typeof node==='object'){if(predicate(node))return node;for(const child of node.children){const result=find(child,predicate);if(result)return result;}}}
const source=fs.readFileSync(process.env.CFIP_TEST_OVERVIEW || path.join(__dirname,'../package/luci-app-cloudflare-ip/htdocs/luci-static/resources/view/cloudflare-ip/overview.js'),'utf8');
function makeView(status,response={success:true,env:{tar:true,jq:null,passwall_installed:false,passwall2_installed:false,homeproxy_installed:false,openclash_installed:false,cfst_installed:null}}){
 const utils={callStatus:()=>Promise.resolve(status),loadSharedCSS(){},waitForServiceReady:()=>new Promise(()=>{}),appendFooter:x=>x,FOOTER_OPTIONS:{},setBusy(){},resetBusy(){},noticeError(){}};
 return new Function('view','ui','rpc','uci','form','utils','E','_','setTimeout',source)(
  {extend:x=>x},{addNotification(){}},{declare:()=>()=>Promise.resolve(response)},{load:()=>Promise.resolve(),get:()=>undefined},{},utils,E,x=>x,()=>{});
}
function row(root,label){const found=find(root,node=>node.tag==='tr'&&node.children[0]&&node.children[0].tag==='th'&&text(node.children[0])===label);assert(found,label+' row missing');return text(found);}
(async()=>{
 for(const bad of [null,{},[],{success:false,error:'controlled status failure',running:false},{running:'false'}]){
  const result=await makeView(bad).load();
  assert(result&&result._loadError instanceof Error,'invalid status must return a renderable load-error state');
  assert.match(result._loadError.message,/Unable to load status:/);
 }
 const status={running:false,env:{}};
 assert.equal(await makeView(status).load(),status);
 let root=makeView(status).render(status);
 for(const label of ['tar','jq','CFST']){
  assert.match(row(root,label),/Unknown/);assert.doesNotMatch(row(root,label),/Missing|Not Installed|Stopped/);
 }
 for(const label of ['PassWall','PassWall2','HomeProxy','OpenClash'])assert.equal(find(root,node=>node.tag==='tr'&&node.children[0]&&text(node.children[0])===label),undefined);
 assert.match(row(root,'Proxy Software'),/✘ Not Installed/);
 const malformed={running:false,env:{tar:'false',jq:null,passwall_installed:'false',openclash_installed:true,cfst_installed:'false'}};
 root=makeView(malformed).render(malformed);
 for(const label of ['tar','jq','CFST'])assert.match(row(root,label),/Unknown/);
 assert.equal(find(root,node=>node.tag==='tr'&&node.children[0]&&text(node.children[0])==='PassWall'),undefined);
 assert.match(row(root,'OpenClash'),/Installed \(Status Unknown\)/);
 const known={running:false,env:{tar:true,jq:false,passwall_installed:true,passwall_running:false,openclash_installed:true,openclash_running:true,cfst_installed:false}};
 root=makeView(known).render(known);
 assert.match(row(root,'tar'),/Installed/);assert.match(row(root,'jq'),/Missing/);
 assert.match(row(root,'PassWall'),/Installed \(Stopped\)/);assert.match(row(root,'OpenClash'),/Running/);assert.match(row(root,'CFST'),/Not Installed/);
 const button=find(root,node=>node.tag==='button'&&text(node).includes('Refresh Environment'));
 await button.attrs.click.call(button);
 assert.match(row(root,'tar'),/Installed/);
 for(const label of ['jq','CFST'])assert.match(row(root,label),/Unknown/);
 for(const label of ['PassWall','PassWall2','HomeProxy','OpenClash'])assert.equal(find(root,node=>node.tag==='tr'&&node.children[0]&&text(node.children[0])===label),undefined);
 assert.match(row(root,'Proxy Software'),/✘ Not Installed/);
 console.log('PASS actual Overview load preserves unknown dependency state and hides unknown proxies before and after refresh');
})().catch(error=>{console.error(error);process.exitCode=1;});
