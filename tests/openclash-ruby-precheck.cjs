'use strict';
// Render the real OpenClash view with the four environment outcomes. This
// complements the real-LuCI restore test; it does not replace it.
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');

String.prototype.format = function(...args) { let i = 0; return this.replace(/%s/g, () => args[i++]); };
function E(tag, attrs = {}, children = []) {
	return { tag, attrs, children: Array.isArray(children) ? children : (children == null ? [] : [children]),
		appendChild(child) { this.children.push(child); return child; },
		removeChild(child) { this.children.splice(this.children.indexOf(child), 1); return child; } };
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
function makeView(env, backupResults = []) {
	const observers = [];
	let backupCalls = 0;
	const window = { IntersectionObserver: class {
		constructor(callback) { this.callback = callback; observers.push(this); }
		observe(target) { this.target = target; }
		disconnect() { this.disconnected = true; }
	} };
	const document = { getElementById() { return null; } };
	const utils = {
		loadSharedCSS() {},
		renderWithFooter(node) { return node; },
		createHandleSave() {},
		createHandleSaveApply() {},
		FOOTER_OPTIONS: {},
		callCheckEnv: () => Promise.resolve(env || {}),
		errorPanel: (title, message, error) => E('div', { 'class': 'alert-message danger' }, [title, message || '', String(error || '')])
	};
	const form = {
		Map: class {
			render() { return Promise.resolve(E('div', { 'class': 'cbi-map' })); }
			section() { return { option() { return { value() {}, depends() {} }; } }; }
		},
		TypedSection: 'typed'
	};
	const view = new Function('view','ui','rpc','uci','form','utils','E','_','setTimeout','window','document', source)(
		{ extend: x => x },
		{ showModal() {}, hideModal() {}, addNotification() {} },
		{ declare: ({ method }) => () => {
			if (method === 'oc-list-backups') {
				backupCalls++;
				const result = backupResults.shift();
				return result instanceof Error ? Promise.reject(result) : Promise.resolve(result || { success: true, backups: [] });
			}
			return Promise.resolve({ success: true });
		} },
		{ load: () => Promise.resolve(), get: () => undefined },
		form, utils, E, x => x, fn => setTimeout(fn, 0), window, document
	);
	view._observers = observers;
	Object.defineProperty(view, 'backupCalls', { get: () => backupCalls });
	return view;
}
async function render(env, backupResults = []) {
	const view = makeView(env, backupResults);
	const loaded = await view.load();
	assert.equal(view.backupCalls, 0, 'load() called the backup RPC eagerly');
	const root = await view.render(loaded);
	if (env.openclash_installed) {
		assert.match(flatten(root), /Backup list loads when this section is reached\./);
		assert.equal(view.backupCalls, 0, 'backup RPC ran before its section was reached');
		const observer = view._observers.find(item => item.target && item.target.attrs.id === 'oc-backups-section');
		assert.ok(observer, 'backup section was not observed');
		observer.callback([{ isIntersecting: true, target: observer.target }]);
		await new Promise(resolve => setTimeout(resolve, 0));
		assert.equal(view.backupCalls, 1, 'backup RPC did not run after section activation');
	}
	return { root, text: flatten(root), view };
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
		const rendered = await render(item.env, [{ success: true, backups: [{ id: '20261001', timestamp: '2026-10-01 10:00:00', size: 1024 }] }]);
		const text = rendered.text;
		for (const expected of item.expect) assert.ok(text.includes(expected), item.name + ' missing: ' + expected);
		for (const absent of item.absent) assert.ok(!text.includes(absent), item.name + ' unexpectedly contains: ' + absent);
		if (item.disabled !== null) {
			const restore = buttons(rendered.root).find(button => flatten(button).includes('Restore'));
			if (restore) assert.equal(restore.attrs.disabled, item.disabled ? '' : null, item.name + ' restore disabled state');
		}
		console.log('PASS ' + item.name);
	}
	const retry = await render({ ...base, ruby_psych: true, ruby_usable: true, ruby_status: 'available' }, [
		{ success: false, error: 'controlled backup list failure' },
		{ success: true, backups: [{ id: 'after-retry', timestamp: '2026-11-26 10:00:00', size: 2048 }] }
	]);
	assert.ok(retry.text.includes('controlled backup list failure'));
	const retryButton = buttons(retry.root).find(button => flatten(button).includes('Retry'));
	assert.ok(retryButton, 'backup list failure did not offer Retry');
	retryButton.attrs.click.call(retryButton);
	await new Promise(resolve => setTimeout(resolve, 0));
	assert.equal(retry.view.backupCalls, 2);
	assert.ok(flatten(retry.root).includes('2026-11-26 10:00:00'), 'Retry did not render the refreshed backup list');
	console.log('PASS actual OpenClash view distinguishes missing Ruby, missing Psych, unusable Ruby and available states');
	console.log('PASS backup list RPC waits for section visibility and retries after an error');
})().catch(error => { console.error(error); process.exitCode = 1; });
