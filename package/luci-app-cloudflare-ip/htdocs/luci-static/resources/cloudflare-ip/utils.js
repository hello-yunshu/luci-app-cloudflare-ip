'use strict';
'require uci';
'require rpc';
'require ui';
'require dom';
'require baseclass';

var FOOTER_VERSION = '@PKG_FULL_VERSION@';
var saveApplySequence = 0;

var callReadConfig = rpc.declare({ object: 'uci', method: 'get', params: [ 'config' ], expect: { values: {} }, reject: true });

var callStatus = rpc.declare({ object: 'cf_ip', method: 'status', expect: { '': {} } });
var callCheckEnv = rpc.declare({ object: 'cf_ip', method: 'check-env', expect: { '': {} } });
var callValidateConfig = rpc.declare({ object: 'cf_ip', method: 'validate-config', params: [ 'candidate' ], expect: { '': {} } });
var callServiceRestart = rpc.declare({ object: 'cf_ip', method: 'restart', expect: { '': {} } });

var FOOTER_OPTIONS = {
	project: _('Cloudflare IP Optimization'),
	repoUrl: 'https://github.com/hello-yunshu/luci-app-cloudflare-ip'
};

function safeApply() {
	return uci.apply().catch(function(e) {
		var message = e && e.message ? e.message : String(e);
		if (e === 5 || /\bubus code 5\b/.test(message) || /No data|未收到数据/.test(message))
			return;
		throw e;
	});
}

function setBusy(button, label) {
	if (!button)
		return;
	button.disabled = true;
	button.setAttribute('aria-busy', 'true');
	if (button.getAttribute('data-original-title') == null)
		button.setAttribute('data-original-title', button.textContent);
	button.textContent = label;
}

function resetBusy(button) {
	if (!button)
		return;
	button.disabled = false;
	button.removeAttribute('aria-busy');
	button.textContent = button.getAttribute('data-original-title') || button.textContent;
	button.removeAttribute('data-original-title');
}

function reloadSoon(delay, isActive) {
	window.setTimeout(function() {
		if (isActive && !isActive()) return;
		window.location.reload();
	}, delay || 1200);
}

function waitForServiceReady(callStatus, options) {
	options = options || {};
	var interval = options.interval || 3000;
	var timeout = options.timeout || 120000;
	var isReady = options.isReady || function(s) {
		return s && s.running && s.last_result !== 'running' && s.jobRunning !== true && s.active_run !== true;
	};
	return new Promise(function(resolve, reject) {
		var settled = false, pollTimer = null, activeTimer = null, deadlineTimer = null;
		function finish(error, status) {
			if (settled) return;
			settled = true;
			[pollTimer, activeTimer, deadlineTimer].forEach(function(timer) {
				if (timer !== null) window.clearTimeout(timer);
			});
			if (error) reject(error); else resolve(status);
		}
		function failure(code, message) {
			var error = new Error(message);
			error.code = code;
			finish(error);
		}
		function active() {
			if (settled) return false;
			if (options.isActive && !options.isActive()) {
				failure('ServiceReadyCancelled', _('Service readiness check was cancelled.'));
				return false;
			}
			return true;
		}
		function checkActive() {
			try {
				if (active()) activeTimer = window.setTimeout(checkActive, interval);
			} catch (error) { finish(error); }
		}
		function poll() {
			try { if (!active()) return; } catch (error) { finish(error); return; }
			Promise.resolve().then(callStatus).then(function(status) {
				if (!active()) return;
				status = status || {};
				if (isReady(status)) finish(null, status);
				else pollTimer = window.setTimeout(poll, interval);
			}).catch(function(error) { finish(error); });
		}
		deadlineTimer = window.setTimeout(function() {
			failure('ServiceReadyTimeout', _('Service did not become ready before the timeout. Check service status and logs.'));
		}, timeout);
		if (options.isActive) checkActive();
		poll();
	});
}

function requireSuccess(result) {
	if (!result || result.success !== true)
		throw new Error(result.error || _('service action failed'));
	return result || {};
}

function buildStagedCandidate() {
	var sections = {
		main: [ 'enabled', 'mode', 'ip_count', 'ip_type', 'speedtest_protocol', 'speedtest_cfcolo',
			'speedtest_dn', 'speedtest_dt', 'speedtest_threads', 'speedtest_ping_count', 'speedtest_tll',
			'speedtest_tl', 'stop_service', 'startup_delay', 'work_dir', 'cron_interval', 'cron_custom',
			'cfst_persist', 'candidate_budget', 'probe_top_count', 'probe_concurrency', 'probe_timeout',
			'measurement_timeout', 'recovery_timeout', 'probe_batch_size', 'max_probe_count',
			'early_stop_enabled', 'source_policy', 'reuse_enabled', 'max_full_optimize_interval',
			'reuse_validation_timeout', 'reuse_loss_limit', 'reuse_ttfb_limit', 'reuse_total_limit',
			'github_mirror', 'verbose' ],
			rill: [ 'enabled', 'mode', 'runtime', 'state_file', 'timeout_ms', 'safe_top_k',
				'min_feedback_samples', 'delayed_feedback_minutes' ],
		lan: [ 'enabled', 'bind_address', 'port' ],
		passwall: [ 'target_domain', 'name_suffix' ],
		openclash: [ 'config', 'target_domain', 'name_suffix', 'transport_filter', 'backup_count' ]
	};
	var candidate = {};
	Object.keys(sections).forEach(function(section) {
		sections[section].forEach(function(option) {
			var value = uci.get('cf_ip', section, option);
			if (value !== undefined && value !== null)
				candidate['cf_ip.' + section + '.' + option] = value;
		});
	});
	return candidate;
}

function configSnapshot(values) {
	if (!values || typeof values !== 'object' || Array.isArray(values) || !Object.keys(values).length)
		throw new Error(_('Unable to verify the applied configuration. Reload and try again.'));
	var snapshot = Object.create(null);
	Object.keys(values).sort().forEach(function(name) {
		var section = values[name], options = Object.create(null);
		if (!section || typeof section !== 'object' || typeof section['.type'] !== 'string')
			throw new Error(_('Unable to verify the applied configuration. Reload and try again.'));
		Object.keys(section).sort().forEach(function(option) {
			if (option.charAt(0) !== '.') {
				var value = section[option];
				options[option] = Array.isArray(value) ? value.map(String) : String(value);
			}
		});
		snapshot[name] = { type: section['.type'], options: options };
	});
	return snapshot;
}

function stagedConfigSnapshot() {
	var sections = Object.create(null);
	uci.sections('cf_ip').forEach(function(section) {
		if (typeof section['.name'] !== 'string' || !section['.name'] || sections[section['.name']])
			throw new Error(_('Unable to verify the applied configuration. Reload and try again.'));
		sections[section['.name']] = section;
	});
	return configSnapshot(sections);
}

function readAppliedConfig(expected) {
	return Promise.all([ callReadConfig('cf_ip'), uci.changes() ]).then(function(result) {
		var values = result[0], changes = result[1];
		if (!changes || typeof changes !== 'object' || Array.isArray(changes))
			throw new Error(_('Unable to verify the applied configuration. Reload and try again.'));
		if (Object.prototype.hasOwnProperty.call(changes, 'cf_ip') && !Array.isArray(changes.cf_ip))
			throw new Error(_('Unable to verify the applied configuration. Reload and try again.'));
		if (changes.cf_ip && changes.cf_ip.length)
			throw new Error(_('Configuration still has uncommitted changes. Apply it again before restarting.'));
		if (JSON.stringify(configSnapshot(values)) !== JSON.stringify(expected))
			throw new Error(_('Applied configuration does not match the saved settings. Reload and review the configuration.'));
		return values;
	});
}

function loadSharedCSS() {
	if (!document.getElementById('cfi-shared-css')) {
		var link = E('link', {
			'id': 'cfi-shared-css',
			'rel': 'stylesheet',
			'href': L.resource('cloudflare-ip/cloudflare-ip.css') + '?v=@PKG_FULL_VERSION@'
		});
		document.head.appendChild(link);
	}
}

function footerSeparator(extraClass) {
	var className = 'ys-tool-footer-separator';
	if (extraClass)
		className += ' ' + extraClass;
	return E('span', { 'class': className }, '\u00a0·\u00a0');
}

function footerIcon(name) {
	var svgNS = 'http://www.w3.org/2000/svg';
	var svg = document.createElementNS(svgNS, 'svg');
	var path = document.createElementNS(svgNS, 'path');

	svg.setAttribute('class', 'ys-tool-footer-link-icon ' + name);
	svg.setAttribute('viewBox', '0 0 24 24');
	svg.setAttribute('width', '14');
	svg.setAttribute('height', '14');
	svg.setAttribute('aria-hidden', 'true');
	svg.setAttribute('focusable', 'false');
	svg.setAttribute('style', 'width:1em;height:1em;max-width:1em;max-height:1em;display:inline-block;flex:0 0 auto;vertical-align:-0.125em');

	if (name === 'github') {
		path.setAttribute('fill', 'currentColor');
		path.setAttribute('d', 'M12 2C6.48 2 2 6.58 2 12.26c0 4.53 2.87 8.37 6.84 9.73.5.09.68-.22.68-.49v-1.9c-2.78.62-3.37-1.22-3.37-1.22-.45-1.19-1.11-1.5-1.11-1.5-.91-.64.07-.63.07-.63 1 .07 1.53 1.06 1.53 1.06.9 1.57 2.35 1.12 2.92.86.09-.67.35-1.12.63-1.38-2.22-.26-4.56-1.14-4.56-5.07 0-1.12.39-2.03 1.03-2.75-.1-.26-.45-1.3.1-2.71 0 0 .84-.28 2.75 1.05A9.36 9.36 0 0 1 12 6.97c.85 0 1.71.12 2.51.34 1.91-1.33 2.75-1.05 2.75-1.05.55 1.41.2 2.45.1 2.71.64.72 1.03 1.63 1.03 2.75 0 3.94-2.34 4.8-4.57 5.06.36.32.68.94.68 1.9v2.82c0 .27.18.59.69.49A10.24 10.24 0 0 0 22 12.26C22 6.58 17.52 2 12 2z');
	} else if (name === 'x') {
		path.setAttribute('fill', 'currentColor');
		path.setAttribute('d', 'M18.244 2.25h3.308l-7.227 8.26 8.502 11.24H16.17l-5.214-6.817L4.99 21.75H1.68l7.73-8.835L1.254 2.25H8.08l4.713 6.231 5.451-6.231zm-1.161 17.52h1.833L7.084 4.126H5.117L17.083 19.77z');
	} else {
		return null;
	}

	svg.appendChild(path);
	return svg;
}

function footerLink(href, label, icon) {
	var children = [];
	var iconNode = icon ? footerIcon(icon) : null;
	if (iconNode)
		children.push(iconNode);
	children.push(E('span', { 'class': 'ys-tool-footer-link-label' }, label));

	return E('a', {
		'class': 'ys-tool-footer-link' + (icon ? ' ' + icon : ''),
		'href': href,
		'target': '_blank',
		'rel': 'noopener noreferrer'
	}, children);
}

function footerVersion(version) {
	var value = version && version !== '-' ? version : FOOTER_VERSION;
	if (!value || value === '-' || value.charAt(0) === '@')
		return '';
	return /^v/i.test(value) ? value : 'v' + value;
}

function renderFooter(options) {
	options = options || {};
	var project = options.project || _('Cloudflare IP Optimization');
	var version = footerVersion(options.version);
	var repoUrl = options.repoUrl || 'https://github.com/hello-yunshu/luci-app-cloudflare-ip';

	return E('footer', { 'class': 'ys-tool-footer' }, [
		E('div', { 'class': 'ys-tool-footer-brand' }, [
			E('span', { 'class': 'ys-tool-footer-mark' }, '云云舒'),
			footerSeparator('ys-tool-footer-title-separator'),
			E('span', { 'class': 'ys-tool-footer-title' }, project),
			version ? footerSeparator('ys-tool-footer-version-separator') : '',
			version ? E('span', { 'class': 'ys-tool-footer-version' }, version) : ''
		]),
		E('div', { 'class': 'ys-tool-footer-links' }, [
			E('span', { 'class': 'ys-tool-footer-project-link' }, footerLink(repoUrl, _('Project'))),
			footerSeparator('ys-tool-footer-project-separator'),
			footerLink('https://github.com/hello-yunshu', 'GitHub', 'github'),
			footerSeparator(),
			footerLink('https://x.com/yunyunyshu', '@云云舒', 'x')
		])
	]);
}

function appendFooter(node, options) {
	loadSharedCSS();
	if (node) {
		if (node.classList && node.classList.contains('cbi-map') && !node.classList.contains('cfi-dashboard'))
			node.classList.add('cfi-form-map');
		node.appendChild(renderFooter(options));
	}
	return node;
}

function renderWithFooter(rendered, options) {
	return Promise.resolve(rendered).then(function(node) {
		return appendFooter(node, options);
	});
}

function createHandleSave(m) {
	m.handleSave = function(ev) {
		var tasks = [];
		document.getElementById('maincontent')
			.querySelectorAll('.cbi-map').forEach(function(map) {
				tasks.push(dom.callClassMethod(map, 'save'));
			});
		return Promise.all(tasks);
	};
}

function createHandleSaveApply(m) {
	var pending = null;
	var generation = (m.__cfipApplyGeneration || 0) + 1;
	m.__cfipApplyGeneration = generation;
	m.handleSaveApply = function(ev, mode) {
		if (pending) return pending;
		var candidate, expected, owner = this;
		var button = ev && ev.currentTarget && ev.currentTarget.tagName === 'BUTTON' ? ev.currentTarget : null;
		var root = m.root, buttonOwner = String(++saveApplySequence);
		function isActive() {
			return m.__cfipApplyGeneration === generation && (!root || root.isConnected !== false) && (!button || button.isConnected !== false);
		}
		function requireActive() {
			if (!isActive()) { var error = new Error('SaveApplyCancelled'); error.code = 'SaveApplyCancelled'; throw error; }
		}
		if (button) button.setAttribute('data-cfi-apply-owner', buttonOwner);
		setBusy(button, _('Applying configuration...'));
		var operation = Promise.resolve().then(function() { requireActive(); return owner.handleSave(ev); }).then(function() {
			requireActive();
			candidate = buildStagedCandidate();
			expected = stagedConfigSnapshot();
			return callValidateConfig(candidate).then(requireSuccess);
		}).then(function() {
			requireActive();
			return safeApply();
		}).then(function() {
			requireActive();
			return readAppliedConfig(expected);
		}).then(function(applied) {
			requireActive();
			if (!applied.main || applied.main.enabled !== '1') {
				ui.addNotification(null, E('p', _('Configuration saved and applied.')), 'info');
				reloadSoon(600, isActive);
				return;
			}

			ui.addNotification(null, E('p', _('Configuration saved. Restarting service...')), 'info');
			return callServiceRestart().then(requireSuccess).then(function() {
				requireActive();
				return waitForServiceReady(callStatus, { isActive: isActive });
			}).then(function(status) {
				requireActive();
				ui.addNotification(null, E('p', _('Configuration applied and service is ready.')), 'info');
				reloadSoon(300, isActive);
			});
		}).catch(function(e) {
			if (!isActive() || (e && e.code === 'SaveApplyCancelled')) return;
			ui.addNotification(null, E('p', _('Unable to apply configuration: %s').format(e.message)), 'error');
		});
		function cleanup() {
			if (button && button.getAttribute('data-cfi-apply-owner') === buttonOwner) {
				resetBusy(button); button.removeAttribute('data-cfi-apply-owner');
			}
			pending = null;
		}
		pending = operation.then(function(value) {
			cleanup(); return value;
		}, function(error) {
			cleanup(); throw error;
		});
		return pending;
	};
}

return baseclass.extend({
	safeApply: safeApply,
	setBusy: setBusy,
	resetBusy: resetBusy,
	reloadSoon: reloadSoon,
	waitForServiceReady: waitForServiceReady,
	requireSuccess: requireSuccess,
	loadSharedCSS: loadSharedCSS,
	renderFooter: renderFooter,
	appendFooter: appendFooter,
	renderWithFooter: renderWithFooter,
	callStatus: callStatus,
	callCheckEnv: callCheckEnv,
	callValidateConfig: callValidateConfig,
	buildStagedCandidate: buildStagedCandidate,
	callServiceRestart: callServiceRestart,
	FOOTER_OPTIONS: FOOTER_OPTIONS,
	createHandleSave: createHandleSave,
	createHandleSaveApply: createHandleSaveApply
});
