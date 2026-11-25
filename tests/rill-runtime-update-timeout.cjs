'use strict';
// A slow package manager must not be reported as a failed Runtime update.
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');

const source = fs.readFileSync(process.env.CFIP_INTELLIGENCE_SOURCE || path.join(__dirname, '../package/luci-app-cloudflare-ip/htdocs/luci-static/resources/view/cloudflare-ip/intelligence.js'), 'utf8');

function load(handlers, notices, errors) {
	let reloads = 0;
	const L = { env: { rpctimeout: 20 } };
	handlers.L = L;
	const storage = new Map();
	const window = {
		setTimeout: fn => { fn(); return 0; },
		sessionStorage: {
			getItem: key => storage.has(key) ? storage.get(key) : null,
			setItem: (key, value) => storage.set(key, String(value)),
			removeItem: key => storage.delete(key)
		}
	};
	const location = { reload() { reloads += 1; } };
	const rpc = { declare: info => (...args) => {
		const handler = handlers[info.method];
		return handler ? handler(...args) : Promise.resolve({});
	} };
	const utils = {
		errorText(error) { return error == null ? '' : (error.message || String(error)); },
		setBusy(button, label) { button.label = label; },
		resetBusy(button) { button.label = null; },
		noticeError(title, message, error) { errors.push({ title, message, error }); }
	};
	const ui = { addNotification(type, node) { notices.push(node); } };
	const E = (tag, ...args) => ({ tag, text: args.filter(a => typeof a === 'string').join(' ') });
	const body = source.replace(/^return view\.extend\(/m, 'view.extend(') +
		'\nreturn { run: runRuntimeManagerAction, reconcile: reconcileRuntimeCheck, state: () => runtimeManagementState };';
	const factory = new Function('view', 'form', 'uci', 'rpc', 'ui', 'utils', 'E', '_', 'L', 'window', 'location', body);
	const api = factory({ extend: x => x }, {}, {}, rpc, ui, utils, E, x => x, L, window, location);
	return { api, L, storage, reloads: () => reloads };
}

function button() {
	return { label: null, setAttribute() {}, removeAttribute() {}, classList: { contains: () => false } };
}

(async () => {
	{
		const notices = [], errors = [];
		let deadlineDuringAction, statusCalls = 0;
		const handlers = {
			update() { deadlineDuringAction = handlers.L.env.rpctimeout; return Promise.reject(new Error('XHR request timed out')); },
			status() { statusCalls += 1; return Promise.resolve(statusCalls === 1 ? { busy: true, ok: true } : { busy: false, ok: true, updateAvailable: false }); }
		};
		const env = load(handlers, notices, errors);
		assert.equal(env.L.env.rpctimeout, 20);
		await env.api.run('update', 'rill-runtime', button(), 'done', 'failed', true);
		assert.equal(deadlineDuringAction, 120, 'package RPCs must raise the LuCI client deadline');
		assert.equal(statusCalls, 2, 'a timeout must wait through busy, then idle');
		assert.equal(errors.length, 0, 'an unresolved timeout must not be reported as a failure');
		assert.equal(env.L.env.rpctimeout, 20, 'the global RPC deadline must be restored');
		assert.match(notices.map(n => n.text).join(' '), /request timed out, but the manager is now idle/);
		assert.equal(env.reloads(), 1, 'the page must refresh so the real state is visible');
	}

	{
		const notices = [], errors = [];
		const env = load({
			update() { return Promise.reject(new Error('XHR request timed out')); },
			status() { return Promise.resolve({ busy: true, ok: true }); }
		}, notices, errors);
		await env.api.run('update', 'rill-runtime', button(), 'done', 'failed', true);
		assert.equal(errors.length, 1);
		assert.equal(errors[0].title, 'The package manager is still busy.');
		assert.equal(env.api.state().busy, true, 'an unverified action must keep the buttons disabled');
		assert.equal(env.L.env.rpctimeout, 20);
		assert.equal(env.reloads(), 0, 'must not reload while the manager is still working');
	}

	{
		const notices = [], errors = [];
		let statusCalls = 0;
		const env = load({
			update() { return Promise.reject(new Error('collected: no candidates')); },
			status() { statusCalls += 1; return Promise.resolve({ busy: false }); }
		}, notices, errors);
		await env.api.run('update', 'rill-runtime', button(), 'done', 'failed', true);
		assert.equal(errors.length, 1);
		assert.equal(errors[0].title, 'failed');
		assert.equal(statusCalls, 0, 'a real failure must not enter the timeout verification path');
	}

	{
		const notices = [], errors = [];
		const env = load({
			update() { return Promise.resolve({ ok: true }); },
			status() { return Promise.resolve({ ok: true, busy: false, updateAvailable: false }); }
		}, notices, errors);
		env.storage.set('cfi.runtime.last-check', JSON.stringify({ at: Date.now() - 60000, hasUpdate: true }));
		await env.api.run('update', 'rill-runtime', button(), 'done', 'failed', true);
		const record = JSON.parse(env.storage.get('cfi.runtime.last-check'));
		assert.equal(record.hasUpdate, false, 'a completed update must retire the stale "update available" verdict');
		assert(record.at > Date.now() - 5000, 'the verdict clock must reflect the post-action observation');
	}

	{
		const notices = [], errors = [];
		const env = load({
			update() { return Promise.resolve({ ok: true }); },
			status() { return Promise.reject(new Error('status RPC failed')); }
		}, notices, errors);
		env.storage.set('cfi.runtime.last-check', JSON.stringify({ at: Date.now() - 60000, hasUpdate: true }));
		await env.api.run('update', 'rill-runtime', button(), 'done', 'failed', true);
		assert.equal(env.storage.has('cfi.runtime.last-check'), false, 'an unverifiable action must drop the stale verdict');
	}

	{
		const notices = [], errors = [];
		const env = load({
			refresh() { return Promise.resolve({ ok: true, updateAvailable: true }); },
			status() { return Promise.resolve({ ok: true, busy: false, updateAvailable: false }); }
		}, notices, errors);
		await env.api.run('refresh', '', button(), 'done', 'failed', true);
		assert.equal(JSON.parse(env.storage.get('cfi.runtime.last-check')).hasUpdate, true,
			'refresh must keep storing its own feed verdict');
	}

	{
		const notices = [], errors = [];
		const env = load({}, notices, errors);
		const checkedAt = Date.now() - 60000;
		env.storage.set('cfi.runtime.last-check', JSON.stringify({ at: checkedAt, hasUpdate: true }));
		env.api.reconcile({ ok: true, updateAvailable: false });
		const retired = JSON.parse(env.storage.get('cfi.runtime.last-check'));
		assert.equal(retired.hasUpdate, false,
			'a stale verdict must be retired on page load once the manager reports no pending update');
		assert.equal(retired.at, checkedAt,
			'retiring a stale verdict must keep the time of the check it came from');
		env.storage.set('cfi.runtime.last-check', JSON.stringify({ at: Date.now() - 60000, hasUpdate: true }));
		env.api.reconcile({ ok: false, helperAvailable: false });
		assert.equal(JSON.parse(env.storage.get('cfi.runtime.last-check')).hasUpdate, true,
			'an unavailable manager must not rewrite a stored verdict');
	}

	console.log('PASS Runtime update timeouts verify manager state and retire stale update verdicts');
})().catch(error => { console.error(error); process.exitCode = 1; });
