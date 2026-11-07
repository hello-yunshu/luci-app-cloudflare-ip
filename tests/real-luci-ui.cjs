#!/usr/bin/env node
'use strict';

/*
 * Real LuCI UI gate.
 *
 * This is intentionally not a fake-DOM fixture: it drives a browser against a
 * real OpenWrt uhttpd/LuCI instance provisioned by
 * tests/real-luci-ui-provision.sh. It asserts interactions that cannot be
 * proven by tests/luci-*.cjs:
 *   1. refreshing sources does not reload the page and keeps a typed draft;
 *   2. log/command text stays readable and Clear Logs uses a LuCI modal whose
 *      cancel path has no side effects;
 *   3. prefers-reduced-motion removes the running status pulse;
 *   4. a rejected cf_ip RPC is shown as an error, not as an empty/not-installed
 *      state.
 */

const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');
const { chromium } = require('playwright');

function arg(name, fallback) {
	const index = process.argv.indexOf('--' + name);
	return index > -1 && process.argv[index + 1] ? process.argv[index + 1] : fallback;
}

const base = arg('base', process.env.CFIP_UI_BASE || 'http://127.0.0.1:18080');
const container = arg('container', process.env.CFIP_UI_CONTAINER || 'cfip-ui-gate');
const password = arg('password', process.env.CFIP_UI_PASSWORD || 'cfip-gate');
const sha = arg('sha', process.env.CFIP_UI_SHA || execFileSync('git', ['rev-parse', '--short', 'HEAD'], { encoding: 'utf8' }).trim());
const evidence = arg('evidence', process.env.CFIP_UI_EVIDENCE || path.join(process.cwd(), 'docs/audits/next-release-evidence', 'ui-gate-' + sha));

fs.mkdirSync(evidence, { recursive: true });

function dockerExec(script) {
	return execFileSync('docker', ['exec', container, 'sh', '-c', script], { encoding: 'utf8' });
}

const report = {
	schemaVersion: 1,
	sha,
	container,
	base,
	evidence,
	scenarios: []
};

function scenario(name, status, details) {
	report.scenarios.push({ name, status, details });
	console.log(`${status} ${name}${details ? ' — ' + details : ''}`);
}

async function login(page) {
	await page.goto(base + '/cgi-bin/luci/', { waitUntil: 'domcontentloaded' });
	const user = page.locator('input[name="luci_username"]');
	if (await user.count()) {
		await user.fill('root');
		await page.locator('input[name="luci_password"]').fill(password);
		const submit = page.locator('button:has-text("Login"), input[type="submit"]');
		if (await submit.count()) {
			await Promise.all([
				page.waitForNavigation({ waitUntil: 'domcontentloaded' }),
				submit.first().click()
			]);
		} else {
			await Promise.all([
				page.waitForNavigation({ waitUntil: 'domcontentloaded' }),
				page.locator('input[name="luci_password"]').press('Enter')
			]);
		}
	}
	const stillLogin = await page.locator('input[name="luci_password"]').count();
	if (stillLogin)
		throw new Error('LuCI login did not create a session');
}

async function run() {
	const executablePath = process.env.PLAYWRIGHT_EXECUTABLE || undefined;
	const browser = await chromium.launch({ headless: true, executablePath });
	const context = await browser.newContext({ viewport: { width: 1280, height: 900 } });
	const page = await context.newPage();
	const consoleErrors = [];
	page.on('console', message => {
		if (message.type() === 'error')
			consoleErrors.push(message.text());
	});

	try {
		await login(page);

		/* Scenario 1: real RPC refresh must not discard a typed draft. */
		await page.goto(base + '/cgi-bin/luci/admin/services/cf_ip/sources', { waitUntil: 'domcontentloaded' });
		await page.locator('button:has-text("Refresh Sources")').waitFor({ timeout: 30000 });
		const budget = page.locator('.cbi-value:has-text("CFST Candidate IP Count") input').first();
		const original = await budget.inputValue();
		const draft = original === '256' ? '128' : '256';
		await budget.fill(draft);
		await page.evaluate(() => { window.__cfipGateSentinel = true; });
		await page.screenshot({ path: path.join(evidence, sha + '-sources-draft.png') });

		await page.locator('button:has-text("Refresh Sources")').click();
		await page.waitForFunction(() => {
			const messages = Array.from(document.querySelectorAll('.alert-message'));
			return messages.some(node => /Unable to refresh sources|Sources refreshed/i.test(node.textContent || ''));
		}, null, { timeout: 30000 });
		const sentinel = await page.evaluate(() => window.__cfipGateSentinel === true);
		const kept = await page.locator('.cbi-value:has-text("CFST Candidate IP Count") input').first().inputValue();
		if (!sentinel)
			throw new Error('refresh reloaded the page');
		if (kept !== draft)
			throw new Error('refresh discarded the draft: ' + kept + ' != ' + draft);
		await page.screenshot({ path: path.join(evidence, sha + '-sources-refresh.png') });
		scenario('sources-refresh-preserves-draft', 'PASS', 'draft=' + draft + ', reload=false');

		/* Scenario 2: readability and LuCI-native destructive confirmation. */
		await page.goto(base + '/cgi-bin/luci/admin/services/cf_ip/logs', { waitUntil: 'domcontentloaded' });
		await page.locator('#log-area').waitFor({ timeout: 30000 });
		await page.waitForTimeout(500);
		const logFont = await page.locator('#log-area').evaluate(el => parseFloat(getComputedStyle(el).fontSize));
		if (!(logFont >= 12))
			throw new Error('log textarea font-size below 12px: ' + logFont);
		const cmdFont = await page.evaluate(() => {
			const el = document.createElement('div');
			el.className = 'cfi-cmd-box';
			el.textContent = 'opkg install curl jq tar';
			document.querySelector('#maincontent').appendChild(el);
			const size = parseFloat(getComputedStyle(el).fontSize);
			el.remove();
			return size;
		});
		if (!(cmdFont >= 12))
			throw new Error('command box font-size below 12px: ' + cmdFont);
		let nativeDialogs = 0;
		let clearRequests = 0;
		page.on('dialog', dialog => {
			nativeDialogs++;
			dialog.dismiss().catch(() => {});
		});
		page.on('request', request => {
			if ((request.postData() || '').includes('clear-log'))
				clearRequests++;
		});
		await page.locator('button:has-text("Clear Logs")').click();
		const modal = page.locator('#modal_overlay .modal[role="dialog"]');
		await modal.waitFor({ timeout: 10000 });
		const modalCount = await modal.count();
		await page.locator('#modal_overlay button:has-text("Cancel")').click();
		await page.waitForTimeout(400);
		const modalClosed = (await page.locator('#modal_overlay .modal:visible').count()) === 0;
		if (!modalCount || !modalClosed || nativeDialogs || clearRequests)
			throw new Error('confirm is not a side-effect-free LuCI modal');
		await page.screenshot({ path: path.join(evidence, sha + '-logs-confirm-modal.png') });
		scenario('luci-modal-and-readable-text', 'PASS', 'log=' + logFont + 'px, cmd=' + cmdFont + 'px');

		/* Scenario 3: prefers-reduced-motion removes the real status pulse. */
		const reduced = await browser.newContext({
			viewport: { width: 1280, height: 900 },
			reducedMotion: 'reduce'
		});
		const reducedPage = await reduced.newPage();
		try {
			await login(reducedPage);
			await reducedPage.goto(base + '/cgi-bin/luci/admin/services/cf_ip/overview', { waitUntil: 'domcontentloaded' });
			await reducedPage.locator('.cfi-status-icon').waitFor({ timeout: 30000 });
			const motion = await reducedPage.evaluate(() => {
				const icon = document.querySelector('.cfi-status-icon');
				icon.classList.add('running-test');
				return getComputedStyle(icon).animationName;
			});
			if (motion !== 'none')
				throw new Error('reduced motion still animates the status icon: ' + motion);
			scenario('reduced-motion-disables-pulse', 'PASS', 'animation=' + motion);
		} finally {
			await reduced.close();
		}

		/* Scenario 4: a rejected cf_ip RPC must render an explicit error. */
		dockerExec('mv /usr/libexec/rpcd/cf_ip /tmp/cf_ip.disabled && /etc/init.d/rpcd restart >/dev/null 2>&1');
		for (let attempt = 0; attempt < 20; attempt++) {
			if (dockerExec('ubus list | grep -qx cf_ip && echo present || echo absent').trim() === 'absent')
				break;
			await page.waitForTimeout(500);
		}
		await login(page);
		await page.goto(base + '/cgi-bin/luci/admin/services/cf_ip/sources', { waitUntil: 'domcontentloaded' });
		await page.locator('text=Unable to load source registry').waitFor({ timeout: 30000 });
		const retry = page.locator('button:has-text("Retry")');
		if (!(await retry.count()))
			throw new Error('RPC error state has no Retry control');
		await page.screenshot({ path: path.join(evidence, sha + '-sources-rpc-error.png') });
		scenario('sources-rpc-error-visible', 'PASS', 'explicit error + Retry');

		report.consoleErrors = consoleErrors;
	} finally {
		try {
			dockerExec('if [ -f /tmp/cf_ip.disabled ]; then mv /tmp/cf_ip.disabled /usr/libexec/rpcd/cf_ip; /etc/init.d/rpcd restart >/dev/null 2>&1; fi');
		} catch (error) {
			console.error('warning: could not restore rpcd fixture: ' + error.message);
		}
		await browser.close();
	}
}

run().then(() => {
	report.openwrt = dockerExec('. /etc/openwrt_release; printf "%s %s" "$DISTRIB_RELEASE" "$DISTRIB_ARCH"').trim();
	report.luci = dockerExec("opkg list-installed luci-base 2>/dev/null | awk '{print $3}'").trim();
	const output = path.join(evidence, 'ui-gate.json');
	fs.writeFileSync(output, JSON.stringify(report, null, 2) + '\n');
	console.log('ui gate: PASS');
	console.log('evidence: ' + output);
}).catch(error => {
	report.openwrt = (() => { try { return dockerExec('. /etc/openwrt_release; printf "%s %s" "$DISTRIB_RELEASE" "$DISTRIB_ARCH"').trim(); } catch (e) { return 'unknown'; } })();
	report.luci = (() => { try { return dockerExec("opkg list-installed luci-base 2>/dev/null | awk '{print $3}'").trim(); } catch (e) { return 'unknown'; } })();
	fs.mkdirSync(evidence, { recursive: true });
	fs.writeFileSync(path.join(evidence, 'ui-gate.json'), JSON.stringify(report, null, 2) + '\n');
	console.error('ui gate: FAIL — ' + (error.stack || error.message));
	process.exit(1);
});
