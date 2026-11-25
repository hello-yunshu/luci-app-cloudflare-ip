'use strict';
// A client-side timeout must not unlock the package action while the manager
// still reports itself busy: unlocking it would queue a duplicate opkg job.
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');

const sourcePath = process.env.CFIP_INTELLIGENCE_SOURCE ||
	path.join(__dirname, '../package/luci-app-cloudflare-ip/htdocs/luci-static/resources/view/cloudflare-ip/intelligence.js');
const source = fs.readFileSync(sourcePath, 'utf8');

if (!String.prototype.format) {
	String.prototype.format = function () {
		const args = Array.prototype.slice.call(arguments);
		return this.replace(/%[sd]/g, () => String(args.shift()))
			.replace(/\{(\d+)\}/g, (m, i) => (args[i] != null ? String(args[i]) : m));
	};
}

function E(tag, attrs, children) {
	const node = {
		tag, attrs: attrs || {}, children: [],
		appendChild(child) { this.children.push(child); return child; },
		querySelector() { return null; },
		querySelectorAll() { return []; },
		addEventListener() {}, removeAttribute(name) {
			if (name === 'disabled')
				this.disabled = false;
		}, setAttribute(name) {
			if (name === 'disabled')
				this.disabled = true;
		}
	};
	for (const child of (Array.isArray(children) ? children : children == null ? [] : [children])) node.appendChild(child);
	return node;
}

const notices = [];

const utils = {
	errorText: error => String(error && error.message ? error.message : error || ''),
	setBusy: button => { button.disabled = true; return function () { button.disabled = false; }; },
	resetBusy: button => { button.disabled = false; },
	noticeError: (title, message) => notices.push({ title, message }),
	loadSharedCSS() {},
	renderWithFooter: node => node
};

const window = {
	setTimeout: fn => { fn(); return 0; },
	location: { reload() {} }
};

const rpc = {
	declare: spec => function () {
		if (spec.object === 'rill-runtime-manager' && spec.method === 'update')
			return Promise.reject(new Error('XHR request timed out'));
		if (spec.object === 'rill-runtime-manager' && spec.method === 'status')
			return Promise.resolve({ busy: true });
		return Promise.resolve({});
	}
};

const body = source.replace(/^return view\.extend\(/m, 'const viewObject = view.extend(') +
	'\nreturn { view: viewObject, runRuntimeManagerAction };';
const moduleUnderTest = new Function('view', 'form', 'uci', 'rpc', 'ui', 'utils', 'E', '_', 'L', 'window', body)(
	{ extend: object => object },
	{ Map: class {}, TypedSection: Symbol(), NamedSection: Symbol(), DummyValue: Symbol(), Flag: Symbol(), ListValue: Symbol(), Value: Symbol(), Button: Symbol() },
	{ load: () => Promise.resolve() },
	rpc,
	{ addNotification() {} },
	utils,
	E,
	text => text,
	{ env: { rpctimeout: 20 } },
	window
);

(async () => {
	const button = E('button', { type: 'button' });
	await moduleUnderTest.runRuntimeManagerAction('update', 'rill-runtime', button, 'done', 'Runtime action failed', true);

	assert.equal(notices.some(n => /still busy/i.test(String(n.title))), true,
		'the timeout path must report that the manager is still busy');
	assert.equal(notices.some(n => n.title === 'Runtime action failed'), false,
		'a client timeout must not be reported as a package failure');
	assert.equal(button.disabled, true,
		'the clicked action must stay disabled while the manager is still busy');

	console.log('PASS runtime action stays locked after a timeout while the manager is still busy');
})().catch(error => { console.error(error); process.exitCode = 1; });
