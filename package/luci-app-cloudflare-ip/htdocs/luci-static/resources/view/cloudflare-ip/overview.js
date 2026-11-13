'use strict';
'require view';
'require ui';
'require rpc';
'require uci';
'require form';
'require cloudflare-ip/utils as utils';

var callRefreshEnv = rpc.declare({
	object: 'cf_ip',
	method: 'refresh-env',
	expect: { '': {} }
});

var callRun = rpc.declare({
	object: 'cf_ip',
	method: 'run',
	expect: { '': {} }
});

var callSpeedtestStatus = rpc.declare({
	object: 'cf_ip',
	method: 'speedtest-status',
	expect: { '': {} }
});

var callServiceStart = rpc.declare({
	object: 'cf_ip',
	method: 'start',
	expect: { '': {} }
});

var callServiceStop = rpc.declare({
	object: 'cf_ip',
	method: 'stop',
	expect: { '': {} }
});

var callDownloadCfst = rpc.declare({
	object: 'cf_ip',
	method: 'download-cfst',
	expect: { '': {} }
});

var SPEEDTEST_POLL_INTERVAL = 3000;

var STATUS_LABELS = {
	scheduled: _('Scheduled'),
	running: _('Running'),
	success: _('Success'),
	warning: _('Warning'),
	error: _('Error'),
	stopped: _('Stopped'),
	unknown: _('Unknown')
};

function translateStatus(status) {
	if (typeof status !== 'string')
		return STATUS_LABELS.unknown || status;
	if (STATUS_LABELS[status])
		return STATUS_LABELS[status];
	if (status.indexOf('success') === 0)
		return STATUS_LABELS.success;
	return status;
}

function showSpeedtestModal() {
	var statusNode = E('span', { 'class': 'label success' }, '\u23F3 ' + _('Running'));
	var logNode = E('textarea', {
		'class': 'cbi-input-textarea cfi-log-area is-loading',
		'rows': 20,
		'readonly': 'readonly'
	}, _('Loading...'));
	var modalOpen = true;

	function setLogText(text) {
		logNode.value = text;
	}

	function update(result) {
		result = result || {};
		var status = result.last_result || STATUS_LABELS.unknown;
		var isRunning = status === 'running';

		if (status === 'success' || (typeof status === 'string' && status.indexOf('success') === 0)) {
			statusNode.className = 'label success';
			statusNode.textContent = '\u2714 ' + translateStatus(status);
		} else if (status === 'running') {
			statusNode.className = 'label success';
			statusNode.textContent = '\u23F3 ' + translateStatus(status);
		} else if (status === 'error') {
			statusNode.className = 'label important';
			statusNode.textContent = '\u2718 ' + translateStatus(status);
		} else {
			statusNode.className = 'label';
			statusNode.textContent = translateStatus(status);
		}

		var logData = result.log_data || {};
		var logs = logData.logs || '';
		if (logs && logs.trim()) {
			logNode.className = 'cbi-input-textarea cfi-log-area';
			setLogText(logs);
			logNode.scrollTop = logNode.scrollHeight;
		} else if (!isRunning) {
			logNode.className = 'cbi-input-textarea cfi-log-area is-empty';
			setLogText(_('No log output yet.'));
		}

		if (modalOpen && isRunning)
			setTimeout(refresh, SPEEDTEST_POLL_INTERVAL);
	}

	function refresh() {
		callSpeedtestStatus().then(update).catch(function(err) {
			logNode.className = 'cbi-input-textarea cfi-log-area is-error';
			setLogText(_('Unable to load status: %s').format(String(err)));
		});
	}

	ui.showModal(_('Speed Test Log'), [
		E('div', { 'class': 'cbi-value' }, [
			E('label', { 'class': 'cbi-value-title' }, _('Status')),
			E('div', { 'class': 'cbi-value-field' }, statusNode)
		]),
		E('div', { 'class': 'cbi-value' }, [
			E('label', { 'class': 'cbi-value-title' }, _('Log')),
			E('div', { 'class': 'cbi-value-field' }, logNode)
		]),
		E('div', { 'class': 'right' }, [
			E('button', { 'class': 'btn', 'click': refresh }, _('Refresh')),
			E('button', {
				'class': 'btn',
				'click': function() {
					modalOpen = false;
					ui.hideModal();
				}
			}, _('Close'))
		])
	]);

	refresh();
}

function waitReadyAndReload() {
	return utils.waitForServiceReady(utils.callStatus).then(function(status) {
		if (status && (status.jobRunning === true || status.active_run === true))
			ui.addNotification(null, E('p', _('Service action completed, but the speed test is still in progress. Refreshing current status.')), 'warning');
		utils.reloadSoon(300);
		return status;
	});
}

function makeEnvBadge(installed, label) {
	if (typeof installed !== 'boolean')
		return E('span', { 'class': 'label' }, '? ' + _('Unknown'));
	if (installed) {
		return E('span', { 'class': 'label success' }, '\u2714 ' + (label || _('Installed')));
	}
	return E('span', { 'class': 'label warning' }, '\u2718 ' + (label || _('Missing')));
}

function makePluginBadge(installed, running) {
	if (typeof installed !== 'boolean')
		return makeEnvBadge(null);
	if (installed && typeof running !== 'boolean')
		return E('span', { 'class': 'label' }, _('Installed (Status Unknown)'));
	if (installed && running) {
		return E('span', { 'class': 'label success' }, '\u2714 ' + _('Running'));
	} else if (installed) {
		return E('span', { 'class': 'label warning' }, '\u26A0 ' + _('Installed (Stopped)'));
	}
	return E('span', { 'class': 'label warning' }, '\u2718 ' + _('Not Installed'));
}

function buildDepSection(missingDeps, pkgManager) {
	if (!missingDeps || missingDeps.length === 0)
		return null;

	var section = E('div', { 'class': 'cbi-section' });
	section.appendChild(E('h3', {}, _('Missing Dependencies & Fix Commands')));
	var installCmd = pkgManager === 'apk' ?
		'apk add --allow-untrusted ' + missingDeps.join(' ') :
		'opkg install ' + missingDeps.join(' ');
	section.appendChild(E('p', {},
		'\u2718 ' + _('Missing dependencies:') + ' ' + missingDeps.join(', ')));
	section.appendChild(E('div', { 'class': 'cfi-cmd-box' }, installCmd));
	return section;
}

return view.extend({
	/* Actions use their own RPC controls; this view has no editable UCI map. */
	handleSave: null,
	handleSaveApply: null,
	handleReset: null,

	load: function() {
		return Promise.all([
			utils.callStatus().catch(function(err) {
				console.error('cloudflare-ip: status RPC failed', err);
				return { _loadError: err };
			}),
			uci.load('cf_ip').catch(function(err) {
				console.error('cloudflare-ip: uci load failed', err);
				return null;
			})
		]).then(function(results) {
			var status = results[0];
			if (status && status._loadError) return status;
			if (!status || typeof status !== 'object' || Array.isArray(status) || status.success === false || typeof status.running !== 'boolean')
				return { _loadError: new Error(_('Unable to load status: %s').format(status && status.error || _('Unknown'))) };
			return status;
		});
	},

	render: function(data) {
		utils.loadSharedCSS();
		data = data || {};

		if (data._loadError)
			return E('div', { 'class': 'cbi-map cfi-dashboard' }, [
				E('h2', { 'name': 'content' }, _('Overview')),
				E('div', { 'class': 'cbi-section' }, [
					E('h3', {}, _('Unable to load status')),
					E('p', {}, _('Retry the page. If it keeps failing, open Logs & Records.')),
					utils.technicalDetails(data._loadError),
					E('button', {
						'class': 'btn cbi-button',
						'click': function() { location.reload(); }
					}, _('Retry'))
				])
			]);

		var running = data.running || false;
		var lastRun = data.last_run || '-';
		var lastResult = data.last_result || '-';
		var mode = data.mode || uci.get('cf_ip', 'main', 'mode') || '-';
		var ipType = data.ip_type || uci.get('cf_ip', 'main', 'ip_type') || '-';
		var ipCount = data.ip_count || 0;
		var speedtestProtocol = data.speedtest_protocol || uci.get('cf_ip', 'main', 'speedtest_protocol') || '-';
		var bestIps = data.best_ips || [];
		var cfstVersion = data.cfst_version || '-';
		var scriptVersion = data.script_version || '-';
		if (scriptVersion.charAt(0) === '@') scriptVersion = '-';
		var error = data.error || '';

		/* v2 idle status nests environment; legacy status exposes root fields. */
		var environment = Object.assign({}, data, data.env || {});
		var envUpdatedAt = environment.updated_at || '';

		var container = E('div', { 'class': 'cbi-map cfi-dashboard' });

		container.appendChild(E('h2', { 'name': 'content' }, _('Overview')));

		var isRunningTest = data.active_run === true || data.jobRunning === true;
		var banner = E('div', {
			'class': 'cbi-section alert-message ' + (isRunningTest || running ? 'success' : 'warning'),
			'role': 'status',
			'aria-live': 'polite',
			'aria-atomic': 'true'
		});
		banner.appendChild(E('h3', {},
			isRunningTest ? _('Speed Test Running') : (running ? _('Service Enabled') : _('Service Stopped'))));
		banner.appendChild(E('p', {}, isRunningTest ?
			_('Cloudflare IP speed test is in progress. Please wait.') :
			(running ?
				_('Cloudflare IP optimization service is enabled and scheduled.') :
				_('Cloudflare IP optimization service is not running. Click Start to begin.'))));
		container.appendChild(banner);

		if (isRunningTest) {
			// Auto-refresh status while speedtest is running; user can click the Running button or Last Result badge to view the log
			utils.waitForServiceReady(utils.callStatus, {
				isActive: function() { return container.isConnected; }
			}).then(function() {
				if (container.isConnected)
					utils.reloadSoon(300);
			}).catch(function() {});
		} else if (running) {
			// Edge case: page loaded right after callRun() but before backend wrote "running" status
			// Re-check after short delay to catch the transition
			setTimeout(function() {
				utils.callStatus().then(function(s) {
					if (s && (s.jobRunning === true || s.active_run === true))
						utils.reloadSoon(300);
				});
			}, 2000);
		}

		var statsGrid = E('div', { 'class': 'cfi-stats-grid' });

		var ipCountClass = ipCount > 0 ? 'cfi-stat-value green' : 'cfi-stat-value';
		statsGrid.appendChild(E('div', { 'class': 'cbi-section cfi-stat-card' }, [
			E('div', { 'class': ipCountClass }, String(ipCount)),
			E('div', { 'class': 'cfi-stat-label' }, _('Best IP Count'))
		]));

		statsGrid.appendChild(E('div', { 'class': 'cbi-section cfi-stat-card' }, [
			E('div', { 'class': 'cfi-stat-value' }, ipType.toUpperCase()),
			E('div', { 'class': 'cfi-stat-label' }, _('IP Type'))
		]));

		statsGrid.appendChild(E('div', { 'class': 'cbi-section cfi-stat-card' }, [
			E('div', { 'class': 'cfi-stat-value' }, speedtestProtocol.toUpperCase()),
			E('div', { 'class': 'cfi-stat-label' }, _('Speed Test Protocol'))
		]));

		container.appendChild(statsGrid);

		var controlSection = E('div', { 'class': 'cbi-section' });
		controlSection.appendChild(E('h3', {}, _('Service Control')));

		var btnGroup = E('div', {});

		if (!running) {
			btnGroup.appendChild(E('button', {
				'class': 'cbi-button cbi-button-apply',
				'click': function() {
					var btn = this;
					utils.setBusy(btn, _('Loading...'));
					return callServiceStart().then(utils.requireSuccess).then(function() {
						ui.addNotification(null, E('p', _('Service started.')), 'info');
						return waitReadyAndReload();
					}).catch(function(e) {
						utils.noticeError(_('Unable to start service.'), _('The service state was not changed.'), e);
						utils.resetBusy(btn);
					});
				}
			}, '\u25B6 ' + _('Start')));
		}

		if (running) {
			btnGroup.appendChild(E('button', {
				'class': 'cbi-button cbi-button-reset',
				'click': function() {
					var btn = this;
					utils.setBusy(btn, _('Loading...'));
					return callServiceStop().then(utils.requireSuccess).then(function() {
						ui.addNotification(null, E('p', _('Service stopped.')), 'info');
						utils.reloadSoon();
					}).catch(function(e) {
						utils.noticeError(_('Unable to stop service.'), _('The service state was not changed.'), e);
						utils.resetBusy(btn);
					});
				}
			}, '\u25A0 ' + _('Stop')));
		}

		btnGroup.appendChild(E('button', {
			'class': 'cbi-button cbi-button-apply',
			'click': function() {
				var btn = this;
				utils.setBusy(btn, _('Loading...'));
				return utils.callServiceRestart().then(utils.requireSuccess).then(function() {
					ui.addNotification(null, E('p', _('Service restarted.')), 'info');
					return waitReadyAndReload();
				}).catch(function(e) {
					utils.noticeError(_('Unable to restart service.'), _('The previous service state was preserved.'), e);
					utils.resetBusy(btn);
				});
			}
		}, '\u21BB ' + _('Restart')));

		if (running) {
			/* Speedtest button: shows "Running..." when test is active, click to view log */
			var speedtestBtn = E('button', {
				'class': 'cbi-button cbi-button-apply',
				'click': function() {
					if (isRunningTest) {
						showSpeedtestModal();
						return;
					}
					var btn = this;
					utils.setBusy(btn, '\u23F3 ' + _('Running...'));
					isRunningTest = true;
					// Trigger speedtest in background (non-blocking RPC)
					return callRun().then(function(result) {
						return utils.waitForRunStatus(utils.callStatus, result, {
							isActive: function() { return container.isConnected; }
						});
					}).then(function() {
						if (container.isConnected) utils.reloadSoon(300, function() { return container.isConnected; });
					}).catch(function(e) {
						if (container.isConnected && e.code !== 'ServiceReadyCancelled')
							utils.noticeError(_('Unable to confirm speed test status.'), _('Check the service status and logs before starting another run.'), e);
						isRunningTest = false;
						utils.resetBusy(btn);
					});
				}
			}, isRunningTest ? '\u23F3 ' + _('Running...') : '\u26A1 ' + _('Run Speed Test'));
			btnGroup.appendChild(speedtestBtn);
		}

		controlSection.appendChild(btnGroup);

		/* CFST button in button group */
		var cfstInstalled = data.cfst_installed || false;
		btnGroup.appendChild(E('button', {
			'class': 'cbi-button cbi-button-apply',
			'click': function() {
				var btn = this;
				utils.setBusy(btn, cfstInstalled ? _('Updating...') : _('Downloading...'));
				ui.addNotification(null, E('p', cfstInstalled
					? _('Updating CFST, please wait...')
					: _('Downloading CFST, please wait...')), 'info');
				return callDownloadCfst().then(function(result) {
					result = result || {};
					if (result.success !== true) {
						utils.noticeError(_('Unable to update CFST.'), _('The existing CFST binary, if any, was left unchanged.'), result.error);
					} else {
						ui.addNotification(null, E('p', _('CFST updated successfully.') + (result.cfst_version ? ' (' + result.cfst_version + ')' : '')), 'info');
						utils.reloadSoon(1500);
					}
					}).catch(function(e) {
						utils.noticeError(_('Unable to update CFST.'), _('The existing CFST binary, if any, was left unchanged.'), e);
				}).finally(function() {
					utils.resetBusy(btn);
				});
			}
		}, cfstInstalled ? '\u21BB ' + _('Update CFST') : '\u2B07 ' + _('Download CFST')));

		container.appendChild(controlSection);

		var infoSection = E('div', { 'class': 'cbi-section' });
		infoSection.appendChild(E('h3', {}, _('Service Information')));

		var infoTable = E('table', { 'class': 'table' });

		infoTable.appendChild(E('tr', {}, [
			E('th', {}, _('Mode')),
			E('td', { 'data-title': _('Mode') }, mode)
		]));

		infoTable.appendChild(E('tr', {}, [
			E('th', {}, _('Last Run Time')),
			E('td', { 'data-title': _('Last Run Time') }, lastRun)
		]));

		var lastResultBadge;
		if (lastResult === 'running') {
			lastResultBadge = E('button', {
				'class': 'cbi-button cbi-button-apply',
				'type': 'button',
				'click': showSpeedtestModal
			}, '\u23F3 ' + translateStatus(lastResult));
		} else if (lastResult === 'warning') {
			lastResultBadge = E('span', { 'class': 'label warning' }, '\u26A0 ' + translateStatus(lastResult));
		} else if (lastResult === 'success' || (typeof lastResult === 'string' && lastResult.indexOf('success') === 0)) {
			lastResultBadge = E('span', { 'class': 'label success' }, '\u2714 ' + translateStatus(lastResult));
		} else if (lastResult === '-' || lastResult === 'unknown' || lastResult === 'scheduled') {
			lastResultBadge = E('span', { 'class': 'label' }, _('Not run yet'));
		} else {
			lastResultBadge = E('span', { 'class': 'label important' }, '\u2718 ' + translateStatus(lastResult));
		}
		infoTable.appendChild(E('tr', {}, [
			E('th', {}, _('Last Result')),
			E('td', { 'data-title': _('Last Result') }, lastResultBadge)
		]));
		if (data.service && data.service.target === 'openclash') {
			var serviceMessage;
			if (data.service.deferredUntilServiceStart) {
				serviceMessage = _('Nodes updated; OpenClash is disabled and the changes will take effect after it is started');
			} else if (data.service.error || error) {
				serviceMessage = E('div', {}, [
					E('p', {}, _('OpenClash apply failed.')),
					utils.technicalDetails(data.service.error || error)
				]);
			} else {
				serviceMessage = data.service.serviceApplied ? _('OpenClash service applied and health verified.') :
					(data.service.recoveryVerified ? _('OpenClash service restored and health verified; new nodes were not applied.') : '');
			}
			if (serviceMessage)
				infoTable.appendChild(E('tr', {}, [
					E('th', {}, _('OpenClash Apply Status')),
					E('td', { 'data-title': _('OpenClash Apply Status') }, serviceMessage)
				]));
		}

		var bestIpsText = bestIps.length > 0 ? bestIps.slice(0, 5).join(', ') + (bestIps.length > 5 ? ' ...' : '') : '-';
		infoTable.appendChild(E('tr', {}, [
			E('th', {}, _('Best IPs')),
			E('td', { 'data-title': _('Best IPs') }, bestIpsText)
		]));

		infoTable.appendChild(E('tr', {}, [
			E('th', {}, _('Script Version')),
			E('td', { 'data-title': _('Script Version') }, scriptVersion)
		]));

		infoTable.appendChild(E('tr', {}, [
			E('th', {}, _('CFST Version')),
			E('td', { 'data-title': _('CFST Version') }, cfstVersion)
		]));

		infoTable.appendChild(E('tr', {}, [
			E('th', {}, _('GitHub')),
			E('td', { 'data-title': _('GitHub') }, E('a', {
				'href': 'https://github.com/hello-yunshu/luci-app-cloudflare-ip',
				'target': '_blank',
				'rel': 'noopener'
			}, 'hello-yunshu/luci-app-cloudflare-ip'))
		]));

		infoSection.appendChild(infoTable);
		container.appendChild(infoSection);

		/* Environment Detection */
		var envSection = E('div', { 'class': 'cbi-section' });
		envSection.appendChild(E('h3', {}, _('Environment Detection')));

		var envTable = E('table', { 'class': 'table' });

		var envItems = [
			{ label: _('tar'), key: 'tar' },
			{ label: _('jq'), key: 'jq' },
			{ label: _('PassWall'), key: 'passwall_installed', plugin: true, runningKey: 'passwall_running' },
			{ label: _('OpenClash'), key: 'openclash_installed', plugin: true, runningKey: 'openclash_running' },
			{ label: _('CFST'), key: 'cfst_installed', cfst: true }
		];

		var envTds = [];
		for (var i = 0; i < envItems.length; i++) {
			var item = envItems[i];
			var val = environment[item.key];
			var badge;

			if (item.plugin) {
				var isRunning = environment[item.runningKey];
				badge = makePluginBadge(val, isRunning);
			} else if (item.cfst) {
				if (typeof val !== 'boolean') {
					badge = makeEnvBadge(null);
				} else if (val) {
					var cfstVer = data.cfst_version || '';
					badge = E('span', { 'class': 'label success' }, '\u2714 ' + (cfstVer ? cfstVer : _('Installed')));
				} else {
					badge = E('span', { 'class': 'label important' }, '\u2718 ' + _('Not Installed'));
				}
			} else {
				badge = makeEnvBadge(val);
			}

			var tdContent = [badge];

			var td = E('td', { 'data-title': item.label }, tdContent);
			envTds.push({ td: td, item: item });
			envTable.appendChild(E('tr', {}, [
				E('th', {}, item.label),
				td
			]));
		}

		envSection.appendChild(envTable);

		var envBtnBar = E('div', {});
		envBtnBar.appendChild(E('button', {
			'class': 'cbi-button cbi-button-apply',
			'click': function() {
				var btn = this;
				utils.setBusy(btn, _('Checking...'));
				return callRefreshEnv().then(function(result) {
					if (!result || result.success !== true)
						throw new Error(result && result.error || _('Error'));
					for (var j = 0; j < envTds.length; j++) {
						var entry = envTds[j];
						var it = entry.item;
						var newVal = result[it.key];
						var newBadge;

						if (it.plugin) {
							var newRunning = result[it.runningKey];
							newBadge = makePluginBadge(newVal, newRunning);
						} else if (it.cfst) {
							if (typeof newVal !== 'boolean') {
								newBadge = makeEnvBadge(null);
							} else if (newVal) {
								var ver = result.cfst_version || '';
								newBadge = E('span', { 'class': 'label success' }, '\u2714 ' + (ver ? ver : _('Installed')));
							} else {
								newBadge = E('span', { 'class': 'label important' }, '\u2718 ' + _('Not Installed'));
							}
						} else {
							newBadge = makeEnvBadge(newVal);
						}

						while (entry.td.firstChild) entry.td.removeChild(entry.td.firstChild);
						entry.td.appendChild(newBadge);
					}

					var newMissing = result.missing_deps || [];
					var newDepSection = buildDepSection(newMissing, result.package_manager || 'opkg');
					if (depSection && depSection.parentNode) {
						var depSectionParent = depSection.parentNode;
						if (newDepSection)
							depSectionParent.replaceChild(newDepSection, depSection);
						else
							depSectionParent.removeChild(depSection);
					} else if (newDepSection) {
						container.insertBefore(newDepSection, envSection.nextSibling);
					}
					depSection = newDepSection;

					utils.resetBusy(btn);
						ui.addNotification(null, E('p', _('Environment detection refreshed.')), 'info');
					}).catch(function(e) {
						utils.noticeError(_('Unable to refresh environment.'), _('The previous environment detection is still shown.'), e);
					utils.resetBusy(btn);
				});
			}
		}, '\u21BB ' + _('Refresh Environment')));
		envSection.appendChild(envBtnBar);
		container.appendChild(envSection);

		var missingDeps = data.missing_deps || [];
		var depSection = buildDepSection(missingDeps, data.package_manager || 'opkg');
		if (depSection)
			container.appendChild(depSection);


		return utils.appendFooter(container, utils.FOOTER_OPTIONS);
	}
});
