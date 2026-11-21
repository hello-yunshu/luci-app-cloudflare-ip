'use strict';
// Exercise the actual Overview render and refresh handlers with a small DOM/RPC fixture.
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
			if (child && typeof child === 'object') child.parentNode = null;
			return child;
		},
		get childNodes() { return this.children; },
		get isConnected() { return true; }
	};
	for (const child of Array.isArray(children) ? children : children == null ? [] : [children])
		node.appendChild(child);
	return node;
}

function text(node) {
	return typeof node === 'string' ? node : !node ? '' : node.children.map(text).join(' ');
}

function findAll(node, predicate, found = []) {
	if (node && typeof node === 'object') {
		if (predicate(node)) found.push(node);
		for (const child of node.children || []) findAll(child, predicate, found);
	}
	return found;
}

const source = fs.readFileSync(path.join(__dirname, '../package/luci-app-cloudflare-ip/htdocs/luci-static/resources/view/cloudflare-ip/overview.js'), 'utf8');
const runtimeManagementSource = fs.readFileSync(path.join(__dirname, '../package/luci-app-cloudflare-ip/htdocs/luci-static/resources/view/cloudflare-ip/intelligence.js'), 'utf8');
const proxyLabels = ['PassWall', 'PassWall2', 'HomeProxy', 'OpenClash'];

function makeOverview(initialEnvironment, refreshedEnvironment) {
	const notices = [];
	const utils = {
		FOOTER_OPTIONS: {},
		loadSharedCSS() {},
		appendFooter: node => node,
		callStatus: () => Promise.resolve({ running: false }),
		waitForServiceReady: () => new Promise(() => {}),
		waitForRunStatus: () => new Promise(() => {}),
		setBusy() {},
		resetBusy() {},
		reloadSoon() {},
		noticeError(title, message, error) { notices.push({ kind: 'error', title, message, error }); },
		requireSuccess(value) { return value; }
	};
	const rpc = {
		declare: ({ method }) => () => Promise.resolve(method === 'refresh-env' ?
			Object.assign({ success: true }, refreshedEnvironment) : { success: true })
	};
	const view = new Function('view', 'ui', 'rpc', 'uci', 'form', 'utils', 'E', '_', 'setTimeout', source)(
		{ extend: value => value },
		{ addNotification(_ctx, _node, kind) { notices.push({ kind }); } },
		rpc,
		{ get: () => undefined },
		{},
		utils,
		E,
		value => value,
		() => {}
	);
	return { root: view.render(Object.assign({ running: false, env: initialEnvironment })), notices };
}

function environmentTable(root) {
	const tables = findAll(root, node => node.tag === 'table' && String(node.attrs.class || '').includes('cfi-env-table'));
	assert.equal(tables.length, 1, 'Overview should render exactly one environment table');
	return tables[0];
}

function rowsFor(table) {
	return table.children.filter(node => node.tag === 'tr').map(row => ({
		label: text(row.children[0]),
		text: text(row)
	}));
}

function proxyRows(table) {
	return rowsFor(table).filter(row => proxyLabels.includes(row.label));
}

async function refresh(root) {
	const button = findAll(root, node => node.tag === 'button' && text(node).includes('Refresh Environment'))[0];
	assert.ok(button, 'Overview should expose the environment refresh action');
	await button.attrs.click.call(button);
}

(async () => {
	const mixed = makeOverview({
		passwall_installed: true, passwall_running: false,
		passwall2_installed: false, passwall2_running: false,
		homeproxy_installed: true, homeproxy_running: true,
		openclash_installed: null, openclash_running: null
	}, {});
	const mixedRows = proxyRows(environmentTable(mixed.root));
	assert.deepEqual(mixedRows.map(row => row.label), ['PassWall', 'HomeProxy'], 'only installed===true proxies should be listed');
	assert.match(mixedRows[0].text, /Installed \(Stopped\)/);
	assert.match(mixedRows[1].text, /Running/);
	assert.doesNotMatch(text(environmentTable(mixed.root)), /Proxy Software.*Not Installed/);

	const empty = makeOverview({
		passwall_installed: false,
		passwall2_installed: false,
		homeproxy_installed: undefined,
		openclash_installed: null
	}, {});
	const emptyRows = rowsFor(environmentTable(empty.root));
	assert.deepEqual(proxyRows(environmentTable(empty.root)), [], 'false and unknown proxy observations should be hidden');
	const emptyProxyMarkers = emptyRows.filter(row => row.label === 'Proxy Software' && /✘ Not Installed/.test(row.text));
	assert.equal(emptyProxyMarkers.length, 1, 'zero installed proxies should render exactly one Proxy Software not-installed marker');

	const changing = makeOverview({
		passwall_installed: true, passwall_running: true,
		passwall2_installed: false, passwall2_running: false,
		homeproxy_installed: false, homeproxy_running: false,
		openclash_installed: false, openclash_running: false
	}, { env: {
		passwall_installed: false, passwall_running: false,
		passwall2_installed: true, passwall2_running: false,
		homeproxy_installed: true, homeproxy_running: true,
		openclash_installed: true, openclash_running: false
	} });
	const changingTable = environmentTable(changing.root);
	assert.deepEqual(proxyRows(changingTable).map(row => row.label), ['PassWall']);
	await refresh(changing.root);
	const refreshedTable = environmentTable(changing.root);
	assert.deepEqual(proxyRows(refreshedTable).map(row => row.label), ['PassWall2', 'HomeProxy', 'OpenClash'], 'refresh should replace the proxy row set with the latest installed detections');
	assert.equal(findAll(refreshedTable, node => node.tag === 'tr' && text(node).includes('Proxy Software')).length, 0, 'refreshed non-empty proxy state should remove the fallback marker');
	assert.deepEqual(changing.notices.map(notice => notice.kind), ['info'], 'successful refresh should report a normal completion notice');
	assert.match(runtimeManagementSource, /\[\s*'_cfi_update',\s*helper\s*&&\s*manager\.cfiUpdateAvailable\s*===\s*true\s*\]/,
		'CFI must show its app update action only for a CFI-specific update');
	assert.doesNotMatch(runtimeManagementSource, /\[\s*'_cfi_update',[^\n]*clientUpdateAvailable/,
		'CFI must not use the aggregate client update alias');
	assert.match(runtimeManagementSource, /\[\s*'_runtime_repair',\s*helper\s*&&\s*manager\.repairAvailable\s*===\s*true\s*\]/,
		'CFI should expose Runtime repair only when the manager confirms it is safe');
	assert.match(runtimeManagementSource, /method:\s*'repair'/,
		'CFI repair must use the dedicated allowlisted RPC method');
	assert.match(runtimeManagementSource, /var managerInstalled = manager\.helperAvailable === true;/,
		'CFI must distinguish an installed helper from a helper that can currently manage the feed');
	assert.match(runtimeManagementSource, /\[\s*'_legacy_cfi_update',\s*!managerInstalled\s*\]/,
		'legacy self-update must only appear when the Runtime Manager package is absent');
	assert.match(runtimeManagementSource, /runRuntimeManagerAction\('install',\s*'rill-runtime'/,
		'Runtime installation must use its fixed allowlisted package ID');
	assert.match(runtimeManagementSource, /runRuntimeManagerAction\('repair',\s*'rill-runtime'/,
		'Runtime repair must use its fixed allowlisted package ID');
	assert.match(runtimeManagementSource, /runRuntimeManagerAction\('update',\s*'rill-runtime'/,
		'Runtime updates must use their fixed allowlisted package ID');
	assert.match(runtimeManagementSource, /manager\.channel === 'legacy-preview'.*legacy-runtime-migration-required/s,
		'legacy Preview installs must remain visible as a migration conflict');
	assert.match(runtimeManagementSource, /var compatibleStable = installed && manager\.channel === 'stable' && manager\.compatible === true;/,
		'Runtime update visibility must require an installed compatible Stable Runtime');
	assert.match(runtimeManagementSource, /'_runtime_update',[\s\S]{0,120}compatibleStable && manager\.updateAvailable === true/,
		'Runtime update visibility must use the manager stable update signal');
	assert.match(runtimeManagementSource, /Legacy Preview Runtime is installed\. Remove it explicitly before installing Stable Runtime; CFI will not remove it\./,
		'CFI must explain that legacy Preview removal is explicit');
	assert.match(runtimeManagementSource, /runRuntimeManagerAction\('update',\s*'luci-app-cloudflare-ip'/,
		'CFI updates must use their fixed allowlisted package ID');
	const packageMakefile = fs.readFileSync(path.join(__dirname, '../package/luci-app-cloudflare-ip/Makefile'), 'utf8');
	const basePackage = packageMakefile.split('define Package/luci-app-cloudflare-ip\n')[1].split('endef')[0];
	assert.match(basePackage, /\+rill-runtime-manager/, 'CFI should depend on the Runtime manager helper');
	assert.doesNotMatch(basePackage, /\+rill-runtime-preview/, 'CFI core must not depend on the optional Runtime executable');
	const acl = JSON.parse(fs.readFileSync(path.join(__dirname, '../package/luci-app-cloudflare-ip/root/usr/share/rpcd/acl.d/luci-app-cloudflare-ip.json'), 'utf8'))['luci-app-cloudflare-ip'];
	assert.deepEqual(acl.read.ubus['rill-runtime-manager'], ['status']);
	assert.deepEqual(acl.write.ubus['rill-runtime-manager'], ['refresh', 'install', 'repair', 'update']);

	console.log('PASS actual Overview proxy detection hides false/unknown rows, shows one empty-state marker, and synchronizes rows after refresh');
	console.log('PASS CFI Runtime UI uses fixed package IDs, manager RPC/ACL, and keeps the Runtime executable optional');
})().catch(error => {
	console.error(error);
	process.exitCode = 1;
});
