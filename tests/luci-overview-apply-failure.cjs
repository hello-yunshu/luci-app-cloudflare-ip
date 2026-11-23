'use strict';
// A rolled-back post-apply failure must explain itself: what happened, whether
// traffic is still working, and what to change. The raw reason stays under
// Technical details. Renders the real Overview view with a small DOM shim.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

function E(tag, attrs = {}, children = []) {
	const node = {
		tag,
		attrs,
		children: [],
		parentNode: null,
		appendChild(child) {
			this.children.push(child);
			if (child && typeof child === 'object') child.parentNode = this;
			return child;
		},
		insertBefore(child, reference) {
			const index = reference == null ? this.children.length : this.children.indexOf(reference);
			if (index < 0) throw new Error('insertBefore reference is not a child');
			this.children.splice(index, 0, child);
			if (child && typeof child === 'object') child.parentNode = this;
			return child;
		},
		replaceChild(child, previous) {
			const index = this.children.indexOf(previous);
			if (index < 0) throw new Error('replaceChild target is not a child');
			this.children[index] = child;
			if (child && typeof child === 'object') child.parentNode = this;
			if (previous && typeof previous === 'object') previous.parentNode = null;
			return previous;
		},
		removeChild(child) {
			const index = this.children.indexOf(child);
			if (index < 0) throw new Error('removeChild target is not a child');
			this.children.splice(index, 1);
			return child;
		},
		addEventListener() {},
		get childNodes() { return this.children; },
		get isConnected() { return true; }
	};
	for (const child of Array.isArray(children) ? children : children == null ? [] : [children])
		node.appendChild(child);
	return node;
}

function text(node) {
	if (typeof node === 'string') return node;
	if (!node || typeof node !== 'object') return '';
	return (node.children || []).map(text).join(' ');
}

function findAll(node, predicate, found = []) {
	if (node && typeof node === 'object') {
		if (predicate(node)) found.push(node);
		for (const child of node.children || []) findAll(child, predicate, found);
	}
	return found;
}

function rowText(root, label) {
	const row = findAll(root, node => node.tag === 'tr' && text(node.children[0]) === label)[0];
	assert.ok(row, 'Overview should render the ' + label + ' row');
	return text(row);
}

const source = fs.readFileSync(path.join(__dirname, '../package/luci-app-cloudflare-ip/htdocs/luci-static/resources/view/cloudflare-ip/overview.js'), 'utf8');

function renderOverview(status) {
	const utils = {
		FOOTER: '',
		FOOTER_OPTIONS: {},
		loadSharedCSS() {},
		appendFooter: node => node,
		callStatus: () => Promise.resolve(status),
		callServiceRestart: () => Promise.resolve({ success: true }),
		waitForServiceReady: () => new Promise(() => {}),
		waitForRunStatus: () => new Promise(() => {}),
		formatTimestamp: value => String(value),
		setBusy() {},
		resetBusy() {},
		reloadSoon() {},
		requireSuccess(value) { return value; },
		noticeError() {},
		technicalDetails(error) {
			return E('details', {}, [
				E('summary', {}, 'Technical details'),
				E('pre', {}, error && error.message ? error.message : String(error || ''))
			]);
		}
	};
	const view = new Function('view', 'ui', 'rpc', 'uci', 'form', 'utils', 'E', '_', 'setTimeout', source)(
		{ extend: value => value },
		{ addNotification() {} },
		{ declare: () => () => Promise.resolve({ success: true }) },
		{ get: () => undefined, load: () => Promise.resolve() },
		{},
		utils,
		E,
		value => value,
		() => {}
	);
	return view.render(Object.assign({ running: false, env: {} }, status));
}

const detail = 'post-apply validation failed: 1/4 probes failed: 103.31.4.56 -> assets.hey.run (timeout) (limit 8s)';
const rolledBack = renderOverview({
	last_result: 'error',
	error: detail,
	best_ips: ['103.31.4.56', '104.17.52.125'],
	service: {
		target: 'openclash',
		serviceApplied: false,
		deferredUntilServiceStart: false,
		recoveryAttempted: true,
		recoveryVerified: true,
		error: null
	},
	transaction: { success: false, reason: 'post_apply_probe_failed', rolledBack: true, recoveryVerified: true }
});

const applyRow = rowText(rolledBack, 'OpenClash Apply Status');
assert.match(applyRow, /New nodes did not pass the live check; the previous configuration was restored automatically\./,
	'a rolled-back validation failure must say the previous configuration was restored');
assert.match(applyRow, /OpenClash is still running the last working nodes, so traffic is unaffected\./,
	'the user must learn that the proxy keeps working');
assert.match(applyRow, /raise Probe Timeout in Advanced settings/,
	'the user must get a concrete next action');
assert.match(applyRow, /1\/4 probes failed: 103\.31\.4\.56 -> assets\.hey\.run \(timeout\)/,
	'the failing probe must stay visible in the technical details');
assert.doesNotMatch(applyRow, /^.*OpenClash apply failed\..*$/, 'the vague sentence must not replace the explanation');
assert.match(rowText(rolledBack, 'Last Result'), /Rolled back/, 'the result badge must flag that a rollback happened');

const generic = renderOverview({
	last_result: 'error',
	error: 'OpenClash provider write failed: permission denied',
	best_ips: ['104.17.52.125'],
	service: { target: 'openclash', serviceApplied: false, deferredUntilServiceStart: false, error: null }
});
const genericRow = rowText(generic, 'OpenClash Apply Status');
assert.match(genericRow, /OpenClash apply failed\./, 'other failures keep the short sentence');
assert.doesNotMatch(genericRow, /restored automatically/, 'unrelated failures must not claim a rollback');
assert.doesNotMatch(rowText(generic, 'Last Result'), /Rolled back/, 'the badge only mentions rollback when it happened');

console.log('PASS Overview explains a rolled-back post-apply failure, keeps the failing probe in technical details, and leaves other failures short');
