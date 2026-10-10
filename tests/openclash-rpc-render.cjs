'use strict';
// Render the real LuCI view using rpcd output and a minimal isolated DOM.
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
String.prototype.format = function(...args) { let i = 0; return this.replace(/%s/g, () => args[i++]); };
function E(tag, attrs = {}, children = []) {
  return { tag, attrs, children: Array.isArray(children) ? children : [children],
    appendChild(child) { this.children.push(child); return child; } };
}
const source = fs.readFileSync(path.join(__dirname, '../package/luci-app-cloudflare-ip/htdocs/luci-static/resources/view/cloudflare-ip/overview.js'), 'utf8');
const utils = { loadSharedCSS() {}, waitForServiceReady: () => new Promise(() => {}), appendFooter: x => x, FOOTER_OPTIONS: {} };
const view = new Function('view','ui','rpc','uci','form','utils','E','_','setTimeout', source)(
  { extend: x => x }, {}, { declare: () => () => Promise.resolve({}) },
  { get: () => undefined }, {}, utils, E, x => x, () => {});
function flatten(node) {
  if (typeof node === 'string') return node;
  if (!node) return '';
  return (node.attrs?.class || '') + ' ' + node.children.map(flatten).join(' ');
}
const status = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
let output = flatten(view.render(status));
assert.match(output, /cfi-badge orange.*Warning/);
assert.match(output, /OpenClash is disabled and the changes will take effect after it is started/);
assert.match(output, /Service Enabled/);
assert.doesNotMatch(output, /service applied and health verified/);
output = flatten(view.render({ ...status, running: false, active_run: true, last_result: 'running' }));
assert.match(output, /running-test/);
output = flatten(view.render({ ...status, last_result: 'error', service: { target:'openclash', nodeFileWritten:true, serviceApplied:false, error:'controller health timeout' } }));
assert.match(output, /cfi-badge red/);
assert.match(output, /controller health timeout/);
output = flatten(view.render({ ...status, last_result:'error', error:'OpenClash enable state is unreadable', service:{ target:'openclash', nodeFileWritten:false, serviceApplied:false } }));
assert.match(output, /OpenClash enable state is unreadable/);
output = flatten(view.render({ ...status, last_result:'error', service:{ target:'openclash', nodeFileWritten:false, serviceApplied:false, recoveryVerified:true } }));
assert.match(output, /service restored and health verified; new nodes were not applied/);
assert.doesNotMatch(output, /service applied and health verified/);
view.render({ running:true, last_result:'success' }); // Legacy status compatibility.
console.log('Actual rpcd status renders warning, active task, failure and recovery-only semantics in LuCI');
