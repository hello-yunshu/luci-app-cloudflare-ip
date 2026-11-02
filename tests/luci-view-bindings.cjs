'use strict';
// Actual view modules against packaged section identities, with form/RPC fixtures.
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const root = process.env.CFIP_TEST_VIEW_ROOT || path.resolve(__dirname, '..');
const config = fs.readFileSync(path.join(root, 'package/luci-app-cloudflare-ip/root/etc/config/cf_ip'), 'utf8');
const sections = [...config.matchAll(/^config\s+(\S+)\s+'([^']+)'/gm)].map(m => ({type:m[1], name:m[2]}));
function E(tag, attrs, children) {
 const node = {tag,attrs,children:[],appendChild(child){this.children.push(child);return child;},get lastChild(){return this.children.at(-1);},get firstChild(){return this.children[0];}};
 for(const child of Array.isArray(children)?children:children==null?[]:[children])node.appendChild(child);
 return node;
}
(async()=>{
 for(const name of ['intelligence','sources']) {
  const visibleOptions = new Set();const calls=[];const options={};
  class Map {
   section(kind, first, second) {
    const matches = sections.filter(s => kind==='named' ? s.name===first && s.type===second : s.type===first);
    return {option(type, key) {if(matches.length)visibleOptions.add(key);return options[key]={value(){},depends(){}};}};
   }
   renderContents(){return Promise.resolve(E('div',{}));}
   render(){return this.renderContents();}
  }
  const utils={loadSharedCSS(){},renderWithFooter:x=>x,
   createHandleSave(map,owner){calls.push(['save',owner]);},createHandleSaveApply(map,owner){calls.push(['apply',owner]);}};
  const form={Map,TypedSection:'typed',NamedSection:'named'};
  const source=fs.readFileSync(path.join(root,'package/luci-app-cloudflare-ip/htdocs/luci-static/resources/view/cloudflare-ip',name+'.js'),'utf8');
  const view=new Function('view','form','uci','rpc','ui','utils','E','_',source)(
   {extend:x=>x},form,{}, {declare:()=>()=>Promise.resolve({})},{},utils,E,x=>x);
  await view.render([{}, {presets:[]}, {sources:[]}]);
  const expected=name==='intelligence'?['source_policy','probe_batch_size','max_probe_count','early_stop_enabled','adaptive_measurement_enabled','adaptive_measurement_mode','_endpoint','_health_state']:['candidate_budget','builtin_sources','bind_address','port'];
  for(const field of expected)assert(visibleOptions.has(field),name+' has no packaged config section for '+field);
  if(name==='intelligence')for(const field of ['_health_summary','_health_state'])assert.equal(options[field].cfgvalue(),'Unknown','missing health evidence reported healthy');
  assert.deepEqual(calls.map(c=>c[0]),['save','apply'],name+' bypasses shared candidate validation/readback');
  assert(calls.every(c=>c[1]===view),name+' binds handlers to the map instead of the view');
 }
 console.log('PASS actual Sources/Intelligence view bindings resolve packaged sections and use shared validated apply on view owner');
})().catch(e=>{console.error(e);process.exitCode=1;});
