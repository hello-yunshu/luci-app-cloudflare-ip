'use strict';
// Assert the Intelligence page information architecture from a real render,
// not from source line numbers. Source greps follow renamed variables and
// comments; this captures the sections/options the view actually builds.
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');

const root = process.env.CFIP_TEST_VIEW_ROOT || path.resolve(__dirname, '..');
const source = fs.readFileSync(path.join(root, 'package/luci-app-cloudflare-ip/htdocs/luci-static/resources/view/cloudflare-ip/intelligence.js'), 'utf8');

if (!String.prototype.format) {
	String.prototype.format = function () {
		const args = Array.prototype.slice.call(arguments);
		return this.replace(/%[sd]/g, () => String(args.shift()))
			.replace(/\{(\d+)\}/g, (m, i) => (args[i] != null ? String(args[i]) : m));
	};
}

const observedAnchors = [];
const rowEffects = {};

const sectionStubs = new Map();
function sectionStub(id) {
	if (!sectionStubs.has(id)) {
		sectionStubs.set(id, {
			children: [],
			appendChild(child) { this.children.push(child); return child; },
			classList: { add() {} }
		});
	}
	return sectionStubs.get(id);
}

/* Return a row-like node so the decoration branches actually run: the package
 * action rows get their display/class set, and the disclosure anchors are
 * resolved through closest('.cbi-section'). Returning null here only checked
 * the selector strings and hid regressions in the folding target. */
function rowStub(id) {
	if (!rowEffects[id])
		rowEffects[id] = { display: undefined, classes: [] };
	const effects = rowEffects[id];
	const style = {};
	Object.defineProperty(style, 'display', {
		get() { return effects.display; },
		set(value) { effects.display = value; }
	});
	return {
		id,
		style,
		classList: {
			add(name) { if (!effects.classes.includes(name)) effects.classes.push(name); }
		},
		querySelector(selector) {
			if (selector === '.cbi-value-field')
				return { textContent: '', appendChild() {} };
			return null;
		},
		closest(selector) { return selector === '.cbi-section' ? sectionStub(id) : null; }
	};
}

function E(tag, attrs, children) {
	const node = {
		tag, attrs: attrs || {}, children: [],
		appendChild(child) { this.children.push(child); return child; },
		querySelector(selector) {
			selector = String(selector || '');
			const exact = /\.cbi-value\[id="([^"]+)"\]/.exec(selector);
			if (exact) {
				observedAnchors.push(exact[1]);
				return rowStub(exact[1]);
			}
			const suffix = /\.cbi-value\[id\$="-([^"]+)"\]/.exec(selector);
			if (suffix)
				return rowStub(suffix[1]);
			return null;
		},
		querySelectorAll() { return []; },
		addEventListener() {}, removeAttribute() {}, setAttribute() {},
		get lastChild() { return this.children.at(-1); },
		get firstChild() { return this.children[0]; }
	};
	for (const child of (Array.isArray(children) ? children : children == null ? [] : [children])) node.appendChild(child);
	return node;
}

function findByClass(node, name) {
	if (!node)
		return null;
	if (String((node.attrs && node.attrs.class) || '').split(/\s+/).includes(name))
		return node;
	for (const child of node.children || []) {
		const hit = findByClass(child, name);
		if (hit)
			return hit;
	}
	return null;
}

const sections = [];

function makeOption(type, key, title) {
	return {
		type, key, title,
		value() {}, depends() {}, renderWidget() { return E('div', {}); }
	};
}

class MapStub {
	constructor(...args) { this.args = args; }
	section(type, first, second, third) {
		const title = typeof third === 'string' ? third : second;
		const section = { type, first, second, title, keys: [] };
		sections.push(section);
		return {
			option(optionType, key, optionTitle) {
				section.keys.push(key);
				return makeOption(optionType, key, optionTitle);
			}
		};
	}
	renderContents() { return Promise.resolve(E('div', {})); }
	render() { return this.renderContents(); }
}

const form = {
	Map: MapStub,
	TypedSection: Symbol('TypedSection'),
	NamedSection: Symbol('NamedSection'),
	DummyValue: Symbol('DummyValue'),
	Flag: Symbol('Flag'),
	ListValue: Symbol('ListValue'),
	Value: Symbol('Value'),
	Button: Symbol('Button')
};

const utils = {
	FOOTER_OPTIONS: {},
	loadSharedCSS() {},
	renderWithFooter: node => node,
	statusLabel: (kind, value) => value == null || value === '' ? 'Unknown' : String(value),
	statusReasons: values => values && values.length ? values.join(', ') : 'None',
	collectUnknownStatusCodes: () => [],
	sourceStateLabel: entry => entry && entry.success === true ? 'Fresh' : 'Not fetched',
	sourceErrorNode: code => code || '—',
	errorPanel: (title, message, error) => E('div', {}, [title, message || '', String(error || '')]),
	errorText: error => String(error == null ? '' : error),
	copyButton: () => E('button', {}),
	noticeError() {},
	setBusy: button => { button.busy = true; return function () { button.busy = false; }; },
	createHandleSave() {},
	createHandleSaveApply() {}
};

const L = { env: { rpctimeout: 20 }, url: value => value };
const window = {
	localStorage: { getItem: () => null, setItem() {} },
	sessionStorage: { getItem: () => null, setItem() {}, removeItem() {} },
	setTimeout: fn => { fn(); return 0; },
	location: { reload() {} }
};

const body = source.replace(/^return view\.extend\(/m, 'const viewObject = view.extend(') +
	'\nreturn { view: viewObject };';

const viewModule = new Function('view', 'form', 'uci', 'rpc', 'ui', 'utils', 'E', '_', 'L', 'window', body)(
	{ extend: object => object },
	form,
	{ load: () => Promise.resolve() },
	{ declare: () => () => Promise.resolve({}) },
	{ addNotification() {} },
	utils,
	E,
	text => text,
	L,
	window
);

function sectionByTitle(title) {
	const found = sections.find(section => section.title === title);
	assert(found, 'Intelligence page has no section titled: ' + title);
	return found;
}

function sectionByKey(key) {
	const found = sections.find(section => section.keys.includes(key));
	assert(found, 'Intelligence page has no option: ' + key);
	return found;
}

(async () => {
	const rendered = await viewModule.view.render([
		{}, {}, {}, {},
		{ ok: true, helperAvailable: true, supported: true, installed: true, channel: 'stable', compatible: true }
	]);

	const coreTitles = ['Rill at a glance', 'Rill Runtime', 'Rill decisions', 'Runtime tuning', 'Live State'];
	const order = coreTitles.map(sectionByTitle).map(section => sections.indexOf(section));
	assert.deepEqual(order, [...order].sort((a, b) => a - b),
		'core sections must keep the safe reading order');
	assert.equal(new Set(order).size, order.length, 'core section titles must be unique');

	const glance = sectionByTitle('Rill at a glance');
	assert.equal(glance.keys[0], 'enabled', 'the enable flag must lead the first glance block');
	assert(glance.keys.indexOf('enabled') < glance.keys.indexOf('_package_manager'),
		'version info must sit after the enable flag');
	assert(glance.keys.indexOf('_package_manager') < glance.keys.indexOf('_authority'),
		'version info must sit next to the enable flag');

	const runtime = sectionByTitle('Rill Runtime');
	assert(runtime.keys.indexOf('_package_check') < runtime.keys.indexOf('_package_refresh'),
		'the last-check verdict must lead the Rill Runtime block');
	assert(runtime.keys.indexOf('_package_refresh') < runtime.keys.indexOf('_runtime_install'),
		'Check for updates must precede mutating package actions');
	for (const key of ['_runtime_install', '_runtime_repair', '_runtime_update', '_runtime_uninstall', '_cfi_update', '_legacy_cfi_update']) {
		assert(runtime.keys.includes(key), 'missing package action: ' + key);
		assert(runtime.keys.indexOf('_package_refresh') < runtime.keys.indexOf(key),
			'mutating package action must follow its verdict row: ' + key);
	}
	assert.equal(sectionByKey('_package_refresh'), runtime,
		'Check for updates must not be moved out of the visible Rill Runtime block');
	assert.equal(sectionByKey('_package_check'), runtime,
		'the check verdict must not be moved out of the visible Rill Runtime block');

	assert.equal(sectionByTitle('Runtime tuning').keys[0], 'timeout_ms',
		'the tuning section must keep its native first-row anchor');
	assert.equal(sectionByTitle('Live State').keys[0], '_channel',
		'the live-state section must keep its native first-row anchor');

	const anchors = observedAnchors;
	assert(Array.isArray(anchors) && anchors.length > 0, 'the rendered view must query advanced disclosure anchors');
	assert.equal(anchors.includes('cbi-cf_ip-rill-_state'), false,
		'a state row must not fold the whole package-management block');
	assert.equal(anchors.includes('cbi-cf_ip-rill-_package_check'), false,
		'the check verdict must stay outside the advanced disclosure');
	assert.equal(anchors.includes('cbi-cf_ip-rill-_package_refresh'), false,
		'Check for updates must stay outside the advanced disclosure');
	assert(anchors.includes('cbi-cf_ip-rill-timeout_ms'), true,
		'tuning must be folded behind the advanced disclosure');
	assert(anchors.includes('cbi-cf_ip-rill-_channel'), true,
		'raw live state must be folded behind the advanced disclosure');

	const collapseBody = findByClass(rendered, 'cfi-collapse-body');
	assert(collapseBody, 'advanced sections must be wrapped in a disclosure body');
	assert.equal(collapseBody.children.length, anchors.length,
		'every advanced anchor must move the section it belongs to into the disclosure body');
	assert.equal(rowEffects['_package_refresh'].display, '',
		'Check for updates must stay visible when the helper is installed');
	assert(rowEffects['_package_refresh'].classes.includes('cfi-runtime-management'),
		'package action rows must be tagged so the busy lock can disable them');
	assert.equal(rowEffects['_runtime_update'].display, 'none',
		'an unavailable mutation must be hidden rather than clickable');
	assert.equal(rowEffects['_runtime_repair'].display, 'none',
		'repair must stay hidden while the manager does not offer it');

	console.log('PASS Intelligence information architecture is asserted from the rendered section/option model');
})().catch(error => { console.error(error); process.exitCode = 1; });
