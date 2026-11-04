'use strict';
// Actual utils: human-readable error text plus expandable technical details,
// and safe fallbacks for unknown status/source codes. Not browser proof.
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const source = fs.readFileSync(path.join(__dirname, '../package/luci-app-cloudflare-ip/htdocs/luci-static/resources/cloudflare-ip/utils.js'), 'utf8');
function E(tag, attrs = {}, children = []) {
 const node = { tag, attrs, children: Array.isArray(children) ? children : [children], appendChild(child) { this.children.push(child); return child; }, addEventListener() {}, get textContent() { return this.children.map(c => typeof c === 'string' ? c : c.textContent || '').join(' '); } };
 return node;
}
function text(node) {
 if (node == null || node === false) return '';
 if (typeof node === 'string') return node + ' ';
 return (node.attrs && node.attrs.class ? node.attrs.class + ' ' : '') + node.children.map(text).join('');
}
const utils = new Function('uci', 'rpc', 'ui', 'dom', 'baseclass', '_', 'window', 'E', source)(
 {}, { declare: () => () => Promise.resolve({}) }, { addNotification() {} }, {}, { extend: x => x },
 x => x, { setTimeout() {} }, E
);
assert.equal(utils.statusLabel('reason', 'timeout'), 'Timeout');
assert.equal(utils.statusLabel('reason', 'weird_code'), 'Unknown');
assert.equal(utils.sourceErrorNode('fetch_failed'), 'Download failed');
const sourceError = text(utils.sourceErrorNode('unknown_source_code'));
assert.match(sourceError, /Source error/);
assert.match(sourceError, /Technical details/);
assert.match(sourceError, /unknown_source_code/);
const unknown = utils.collectUnknownStatusCodes({ fallbackReason: 'future_code', intelligence: { inspect: { lastError: 'future_error' } } });
assert.deepEqual(unknown, ['fallbackReason=future_code', 'intelligence.inspect.lastError=future_error']);
const notice = text(utils.errorNotice('Unable to start service.', 'The service state was not changed.', { message: 'raw backend code' }));
assert.match(notice, /Unable to start service\./);
assert.match(notice, /The service state was not changed\./);
assert.match(notice, /Technical details/);
assert.match(notice, /raw backend code/);
console.log('PASS actual utils separates human error text from expandable technical details and handles unknown codes');
