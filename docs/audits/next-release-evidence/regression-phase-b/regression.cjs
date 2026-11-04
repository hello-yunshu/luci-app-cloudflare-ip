#!/usr/bin/env node
'use strict';

/*
 * Phase B real-container branch regression. Unlike tests/luci-*.cjs this uses
 * a real uhttpd/LuCI session and the real cf_ip rpcd backend.
 */

const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');
const { chromium } = require('playwright');

const container = process.env.CFIP_UI_CONTAINER || 'cfip-ui-gate';
const base = process.env.CFIP_UI_BASE || 'http://127.0.0.1:18080';
const password = process.env.CFIP_UI_PASSWORD || 'cfip-gate';
const evidence = process.env.CFIP_UI_EVIDENCE || path.join(process.cwd(), 'docs/audits/next-release-evidence/regression-phase-b');
const sha = process.env.CFIP_UI_SHA || execFileSync('git', ['rev-parse', '--short', 'HEAD'], { encoding: 'utf8' }).trim();
fs.mkdirSync(evidence, { recursive: true });

function dockerExec(script) {
	return execFileSync('docker', ['exec', container, 'sh', '-c', script], { encoding: 'utf8' });
}

const report = { schemaVersion: 1, sha, container, base, scenarios: [] };
function record(name, status, details) {
	report.scenarios.push({ name, status, details });
	console.log(`${status} ${name}${details ? ' — ' + details : ''}`);
}

async function login(page) {
	await page.goto(base + '/cgi-bin/luci/', { waitUntil: 'domcontentloaded' });
	const user = page.locator('input[name="luci_username"]');
	if (await user.count()) {
		await user.fill('root');
		await page.locator('input[name="luci_password"]').fill(password);
		await Promise.all([
			page.waitForNavigation({ waitUntil: 'domcontentloaded' }),
			page.locator('input[name="luci_password"]').press('Enter')
		]);
	}
	if (await page.locator('input[name="luci_password"]').count())
		throw new Error('login failed');
}

async function waitView(page) {
	await page.waitForFunction(() => {
		const text = (document.querySelector('#maincontent') || document.body).innerText;
		return !/Loading view|加载视图中/.test(text);
	}, null, { timeout: 20000 });
}

(async () => {
	const browser = await chromium.launch({ headless: true, executablePath: process.env.PLAYWRIGHT_EXECUTABLE || undefined });
	const context = await browser.newContext({ viewport: { width: 1280, height: 900 }, colorScheme: 'dark' });
	await context.addInitScript(() => localStorage.setItem('aurora.theme', 'dark'));
	const page = await context.newPage();
	try {
		await login(page);

		dockerExec(`mkdir -p /etc/openclash/config /etc/cf_ip
for controller in openclash passwall; do
  [ -x /etc/init.d/$controller ] || printf '#!/bin/sh\\nexit 0\\n' > /etc/init.d/$controller
  chmod +x /etc/init.d/$controller
done
printf 'proxies: []\\n' > /etc/openclash/config/config.yaml
printf 'proxies: []\\n' > /etc/openclash/config/config.yaml.bak.20261103193000
chmod 700 /etc/cf_ip /etc/openclash /etc/openclash/config
chmod 600 /etc/openclash/config/config.yaml /etc/openclash/config/config.yaml.bak.20261103193000`);

		/* Fixture-only routes expose the same real view without the fs depends
		 * guard, so the not-installed branch stays reachable in real LuCI. */
		dockerExec(`cat > /usr/share/luci/menu.d/zz-cfip-fixture.json <<'EOF'
{"admin/services/cf_ip/openclash-test":{"title":"OpenClash Test","order":98,"action":{"type":"view","path":"cloudflare-ip/openclash"}},
"admin/services/cf_ip/passwall-test":{"title":"PassWall Test","order":99,"action":{"type":"view","path":"cloudflare-ip/passwall"}}}
EOF
rm -rf /tmp/luci-indexcache* /tmp/luci-modulecache`);

		dockerExec('mv /etc/init.d/openclash /tmp/openclash.disabled');
		await page.goto(base + '/cgi-bin/luci/admin/services/cf_ip/openclash-test', { waitUntil: 'domcontentloaded' });
		await page.getByText('OpenClash Not Found').waitFor({ timeout: 20000 });
		await page.screenshot({ path: path.join(evidence, sha + '-openclash-not-installed.png') });
		record('openclash-not-installed', 'PASS', 'real view + real check-env');
		dockerExec('mv /tmp/openclash.disabled /etc/init.d/openclash');

		dockerExec('mv /etc/init.d/passwall /tmp/passwall.disabled');
		await page.goto(base + '/cgi-bin/luci/admin/services/cf_ip/passwall-test', { waitUntil: 'domcontentloaded' });
		await page.getByText('PassWall Not Found').waitFor({ timeout: 20000 });
		await page.screenshot({ path: path.join(evidence, sha + '-passwall-not-installed.png') });
		record('passwall-not-installed', 'PASS', 'real view + real check-env');
		dockerExec('mv /tmp/passwall.disabled /etc/init.d/passwall; rm -rf /tmp/luci-indexcache* /tmp/luci-modulecache');

		dockerExec('mv /usr/libexec/rpcd/cf_ip /tmp/cf_ip.disabled && /etc/init.d/rpcd restart >/dev/null 2>&1');
		for (let attempt = 0; attempt < 20; attempt++) {
			if (dockerExec('ubus list | grep -qx cf_ip && echo present || echo absent').trim() === 'absent')
				break;
			await page.waitForTimeout(500);
		}
		await login(page);
		await page.goto(base + '/cgi-bin/luci/admin/services/cf_ip/openclash-test', { waitUntil: 'domcontentloaded' });
		await page.getByText('Unable to check OpenClash environment').waitFor({ timeout: 20000 });
		await page.screenshot({ path: path.join(evidence, sha + '-openclash-rpc-error.png') });
		record('openclash-rpc-error-visible', 'PASS', 'explicit error, not "not installed"');

		await page.goto(base + '/cgi-bin/luci/admin/services/cf_ip/passwall-test', { waitUntil: 'domcontentloaded' });
		await page.getByText('Unable to check PassWall environment').waitFor({ timeout: 20000 });
		await page.screenshot({ path: path.join(evidence, sha + '-passwall-rpc-error.png') });
		record('passwall-rpc-error-visible', 'PASS', 'explicit error, not "not installed"');

		await page.goto(base + '/cgi-bin/luci/admin/services/cf_ip/settings', { waitUntil: 'domcontentloaded' });
		await page.getByText(/Unable to check the proxy environment/).waitFor({ timeout: 20000 });
		await page.screenshot({ path: path.join(evidence, sha + '-settings-rpc-error.png') });
		record('settings-rpc-error-visible', 'PASS', 'explicit environment error, not "no proxy detected"');

		dockerExec('mv /tmp/cf_ip.disabled /usr/libexec/rpcd/cf_ip && /etc/init.d/rpcd restart >/dev/null 2>&1');
		for (let attempt = 0; attempt < 20; attempt++) {
			if (dockerExec('ubus list | grep -qx cf_ip && echo present || echo absent').trim() === 'present')
				break;
			await page.waitForTimeout(500);
		}
		await login(page);

		/* Backup delete failure is driven through the real UI and real rpcd. */
		dockerExec(`chmod 700 /etc/openclash /etc/openclash/config /etc/cf_ip
chmod 600 /etc/openclash/config/config.yaml /etc/openclash/config/config.yaml.bak.20261103193000`);
		await page.goto(base + '/cgi-bin/luci/admin/services/cf_ip/openclash', { waitUntil: 'domcontentloaded' });
		await page.waitForTimeout(1000);
		await waitView(page);
		const deleteButton = page.locator('button:has-text("Delete")').first();
		try {
			await deleteButton.waitFor({ timeout: 20000 });
		} catch (error) {
			console.log('DEBUG delete button missing, content=' + (await page.locator('#maincontent').innerText()).slice(0, 300).replace(/\n/g, ' | '));
			await page.reload({ waitUntil: 'domcontentloaded' });
			await waitView(page);
			await deleteButton.waitFor({ timeout: 20000 });
		}
		await page.locator('button:has-text("Delete")').first().click();
		await page.locator('.modal').waitFor({ timeout: 10000 });
		await page.evaluate(() => { window.__cfipDeleteSentinel = true; });
		dockerExec(`mv /bin/rm /bin/rm.real
printf '#!/bin/sh\\nexit 1\\n' > /bin/rm
chmod +x /bin/rm`);
		await page.locator('.modal button:has-text("Delete")').click();
		await page.waitForFunction(() => Array.from(document.querySelectorAll('.alert-message'))
			.some(node => /Unable to delete backup/.test(node.textContent || '')), null, { timeout: 20000 });
		const sentinel = await page.evaluate(() => window.__cfipDeleteSentinel === true);
		if (!sentinel)
			throw new Error('delete failure reloaded the page');
		if (dockerExec('test -f /etc/openclash/config/config.yaml.bak.20261103193000 && echo present || echo missing').trim() !== 'present')
			throw new Error('delete failure removed the backup');
		await page.screenshot({ path: path.join(evidence, sha + '-openclash-delete-failure.png') });
		record('openclash-delete-failure', 'PASS', 'error notification, no reload, backup retained');
		dockerExec('mv /bin/rm.real /bin/rm');

		/* Rill reset must hit the real backend and refresh the page. */
		dockerExec('rm -f /etc/cf_ip/rill-state-meta.json');
		await page.goto(base + '/cgi-bin/luci/admin/services/cf_ip/intelligence', { waitUntil: 'domcontentloaded' });
		await waitView(page);
		await page.locator('button:has-text("Reset learning state")').click();
		await page.locator('.modal').waitFor({ timeout: 10000 });
		await page.evaluate(() => { window.__cfipResetSentinel = true; });
		await page.locator('.modal button:has-text("Reset")').click();
		await page.waitForFunction(() => window.__cfipResetSentinel === undefined, null, { timeout: 15000 });
		await page.waitForLoadState('domcontentloaded');
		const meta = dockerExec("cat /etc/cf_ip/rill-state-meta.json 2>/dev/null");
		if (!/"resetReason"\s*:\s*"manual_reset"/.test(meta))
			throw new Error('real Rill reset did not write manual_reset metadata');
		await page.screenshot({ path: path.join(evidence, sha + '-rill-reset-after-reload.png') });
		record('rill-reset-refreshes-status', 'PASS', 'real rill-reset + page reload');

		dockerExec('rm -f /usr/share/luci/menu.d/zz-cfip-fixture.json; rm -rf /tmp/luci-indexcache* /tmp/luci-modulecache');
		report.status = 'PASS';
	} finally {
		await browser.close();
		dockerExec(`if [ -f /tmp/openclash.disabled ]; then mv /tmp/openclash.disabled /etc/init.d/openclash; fi
if [ -f /tmp/passwall.disabled ]; then mv /tmp/passwall.disabled /etc/init.d/passwall; fi
if [ -f /tmp/cf_ip.disabled ]; then mv /tmp/cf_ip.disabled /usr/libexec/rpcd/cf_ip; /etc/init.d/rpcd restart >/dev/null 2>&1; fi
if [ -f /bin/rm.real ]; then mv /bin/rm.real /bin/rm; fi
rm -f /usr/share/luci/menu.d/zz-cfip-fixture.json
rm -rf /tmp/luci-indexcache* /tmp/luci-modulecache`);
	}
	const output = path.join(evidence, 'regression.json');
	fs.writeFileSync(output, JSON.stringify(report, null, 2) + '\n');
	console.log('regression: PASS');
	console.log('evidence: ' + output);
})().catch(error => {
	report.status = 'FAIL';
	report.error = error.stack || error.message;
	fs.writeFileSync(path.join(evidence, 'regression.json'), JSON.stringify(report, null, 2) + '\n');
	console.error('regression: FAIL — ' + report.error);
	process.exit(1);
});
