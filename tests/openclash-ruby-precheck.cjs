'use strict';
// Render the real OpenClash view with the four environment outcomes. This
// complements the real-LuCI restore test; it does not replace it.
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');

String.prototype.format = function(...args) { let i = 0; return this.replace(/%s/g, () => args[i++]); };
function E(tag, attrs = {}, children = []) {
	return { tag, attrs, children: Array.isArray(children) ? children : (children == null ? [] : [children]),
		appendChild(child) { this.children.push(child); return child; } };
}
function flatten(node) {
	if (node == null || node === false) return '';
	if (typeof node === 'string') return node + ' ';
	return (node.attrs && node.attrs.disabled !== undefined && node.attrs.disabled !== null ? 'disabled ' : '') +
		(node.attrs && node.attrs['class'] ? node.attrs['class'] + ' ' : '') +
		node.children.map(flatten).join('');
}
function buttons(node, out = []) {
	if (!node || typeof node !== 'object') return out;
	if (node.tag === 'button') out.push(node);
	for (const child of node.children || []) buttons(child, out);
	return out;
}

const source = fs.readFileSync(path.join(__dirname, '../package/luci-app-cloudflare-ip/htdocs/luci-static/resources/view/cloudflare-ip/openclash.js'), 'utf8');
function makeView() {
	const utils = {
		loadSharedCSS() {},
		renderWithFooter(node) { return node; },
		createHandleSave() {},
		createHandleSaveApply() {},
		FOOTER_OPTIONS: {},
		callCheckEnv: () => Promise.resolve({})
	};
	const form = {
		Map: class {
			render() { return Promise.resolve(E('div', { 'class': 'cbi-map' })); }
			section() { return { option() { return { value() {}, depends() {} }; } }; }
		},
		TypedSection: 'typed'
	};
	return new Function('view','ui','rpc','uci','form','utils','E','_','setTimeout', source)(
		{ extend: x => x },
		{ showModal() {}, hideModal() {}, addNotification() {} },
		{ declare: () => () => Promise.resolve({}) },
		{ load: () => Promise.resolve(), get: () => undefined },
		form, utils, E, x => x, () => {}
	);
}
async function render(env) {
	const view = makeView();
	const backups = { success: true, backups: [{ id: '20261001', timestamp: '2026-10-01 10:00:00', size: 1024 }] };
	return flatten(await view.render([{}, env, backups]));
}
const base = { openclash_installed: true, openclash_running: true, package_manager: 'opkg' };
const cases = [
	{ name: 'ruby-missing', env: { ...base, ruby_psych: false, ruby_usable: false, ruby_status: 'ruby_missing' },
		expect: ['OpenClash is installed, but restoring a backup needs Ruby', 'Ruby is not installed.', 'Next step: opkg install ruby ruby-psych'], absent: ['OpenClash Not Found'], disabled: true },
	{ name: 'psych-missing', env: { ...base, ruby_psych: false, ruby_usable: true, ruby_status: 'psych_missing' },
		expect: ['Psych YAML module is missing', 'Next step: opkg install ruby-psych'], absent: ['OpenClash Not Found', 'segmentation fault'], disabled: true },
	{ name: 'ruby-unusable', env: { ...base, ruby_psych: false, ruby_usable: false, ruby_status: 'ruby_unusable' },
		expect: ['exits with a segmentation fault', 'Next step: Use firmware with a working Ruby/Psych'], absent: ['OpenClash Not Found', 'Next step: opkg'], disabled: true },
	{ name: 'available', env: { ...base, ruby_psych: true, ruby_usable: true, ruby_status: 'available', openclash_restore_available: true },
		expect: ['Config Backups'], absent: ['restoring a backup needs Ruby', 'OpenClash Not Found'], disabled: false },
	{ name: 'openclash-missing', env: { openclash_installed: false, ruby_psych: true, ruby_usable: true, ruby_status: 'available' },
		expect: ['OpenClash Not Found'], absent: ['restoring a backup needs Ruby'], disabled: null }
];
(async () => {
	for (const item of cases) {
		const text = await render(item.env);
		for (const expected of item.expect) assert.ok(text.includes(expected), item.name + ' missing: ' + expected);
		for (const absent of item.absent) assert.ok(!text.includes(absent), item.name + ' unexpectedly contains: ' + absent);
		if (item.disabled !== null) {
			const restore = buttons(await (async () => {
				const view = makeView();
				return view.render([{}, item.env, { success: true, backups: [{ id: '20261001', size: 1024 }] }]);
			})()).find(button => flatten(button).includes('Restore'));
			if (restore) assert.equal(restore.attrs.disabled, item.disabled ? '' : null, item.name + ' restore disabled state');
		}
		console.log('PASS ' + item.name);
	}
	console.log('PASS actual OpenClash view distinguishes missing Ruby, missing Psych, unusable Ruby and available states');
})().catch(error => { console.error(error); process.exitCode = 1; });
