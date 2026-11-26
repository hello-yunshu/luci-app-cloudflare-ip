'use strict';
'require view';
'require ui';
'require rpc';
'require cloudflare-ip/utils as utils';

var callReadLog = rpc.declare({ object: 'cf_ip', method: 'read-log', expect: { '': {} } });
var callClearLog = rpc.declare({ object: 'cf_ip', method: 'clear-log', expect: { '': {} } });
var callIpHistory = rpc.declare({ object: 'cf_ip', method: 'ip-history', expect: { '': {} } });
var callRillDiagnostics = rpc.declare({ object: 'cf_ip', method: 'rill-diagnostics', expect: { '': {} } });

return view.extend({
	/* Actions use their own RPC controls; this view has no editable UCI map. */
	handleSave: null,
	handleSaveApply: null,
	handleReset: null,

	load: function() {
		return Promise.resolve({});
	},

	render: function(data) {
		utils.loadSharedCSS();
		var historyData = data || {};

		var container = E('div', { 'class': 'cbi-map cfi-dashboard' });

		container.appendChild(E('h2', { 'name': 'content' }, _('Logs & Records')));

		var intelligenceSection = E('div', { 'class': 'cbi-section', 'id': 'cfi-rill-diagnostics' });
		intelligenceSection.appendChild(E('h3', {}, _('Rill Diagnostics')));
		var diagnosticsStatus = E('p', {
			'class': 'cbi-value-description cfi-rill-diagnostics-loading',
			'role': 'status',
			'aria-live': 'polite',
			'hidden': 'hidden'
		}, _('Loading...'));
		var diagnosticsContent = E('div', { 'class': 'cfi-rill-diagnostics-content', 'hidden': 'hidden' });
		intelligenceSection.appendChild(diagnosticsStatus);
		intelligenceSection.appendChild(diagnosticsContent);

		function renderDiagnostics(diagnostics, error) {
			while (diagnosticsContent.firstChild)
				diagnosticsContent.removeChild(diagnosticsContent.firstChild);
			diagnostics = diagnostics || {};
			if (error || diagnostics.success !== true) {
				var retryButton = E('button', {
					'class': 'cbi-button cbi-button-apply',
					'type': 'button',
					'click': function() {
						var button = this;
						diagnosticsStatus.hidden = false;
						diagnosticsStatus.textContent = _('Loading...');
						diagnosticsContent.hidden = true;
						utils.setBusy(button, _('Loading...'));
						return callRillDiagnostics().then(function(result) {
							renderDiagnostics(result);
						}).catch(function(e) {
							renderDiagnostics(null, e);
						}).finally(function() {
							utils.resetBusy(button);
						});
					}
				}, _('Retry'));
				diagnosticsContent.appendChild(E('div', { 'class': 'alert-message danger', 'role': 'alert' }, [
					E('p', {}, _('Diagnostics unavailable. Check the service status, then try again.')),
					E('details', {}, [
						E('summary', {}, _('Technical details')),
						E('pre', { 'class': 'cfi-log-area cfi-log-pre' }, error ? utils.errorText(error) : (diagnostics.error || _('Unknown')))
					]),
					retryButton
				]));
			} else {
				diagnosticsContent.appendChild(E('pre', { 'class': 'cfi-log-area cfi-log-pre cfi-log-pre-tall' }, JSON.stringify({
					runtime: diagnostics.runtime || {},
					qualification: diagnostics.qualification || {},
					sourcePolicy: diagnostics.sourcePolicy || {},
					reusePolicy: diagnostics.reusePolicy || {},
					prefixIntelligence: diagnostics.prefixIntelligence || {},
					coloIntelligence: diagnostics.coloIntelligence || {},
					pendingFeedback: diagnostics.pendingFeedback || [],
					stateMeta: diagnostics.stateMeta || {}
				}, null, 2)));
			}
			diagnosticsStatus.hidden = true;
			diagnosticsContent.hidden = false;
		}

		/* Recent Logs */
		var logSection = E('div', { 'class': 'cbi-section' });
		logSection.appendChild(E('h3', {}, _('Recent Logs')));

		var logArea = E('textarea', {
			'class': 'cbi-input-textarea cfi-log-area is-loading',
			'id': 'log-area',
			'rows': 4,
			'readonly': 'readonly'
		}, '');
		var logDetails = E('details', { 'class': 'cfi-error-details', 'hidden': true });

		var logLevel = E('select', { 'class': 'cfi-log-level' }, [
			E('option', { 'value': 'all' }, _('All')),
			E('option', { 'value': 'error' }, _('Error')),
			E('option', { 'value': 'warning' }, _('Warning'))
		]);
		var logKeyword = E('input', {
			'class': 'cbi-input-text cfi-log-filter',
			'type': 'text',
			'placeholder': _('Filter')
		});
		var rawLogs = null;

		function setLogText(text) {
			logArea.value = text;
		}

		function matchingLines(text) {
			var keyword = (logKeyword.value || '').trim().toLowerCase();
			var level = logLevel.value;
			return text.split('\n').filter(function(line) {
				if (keyword && line.toLowerCase().indexOf(keyword) === -1)
					return false;
				if (level === 'error' && !/\b(error|failed|failure|fatal|exception)\b/i.test(line))
					return false;
				if (level === 'warning' && !/\bwarn(?:ing|ings)?\b/i.test(line))
					return false;
				return true;
			}).join('\n');
		}

		function applyLogFilter() {
			if (rawLogs === null)
				return;
			if (!rawLogs || !rawLogs.trim()) {
				logArea.className = 'cbi-input-textarea cfi-log-area is-empty';
				logArea.rows = 4;
				setLogText(_('No logs found.'));
				return;
			}
			var filtered = matchingLines(rawLogs);
			if (!filtered.trim()) {
				logArea.className = 'cbi-input-textarea cfi-log-area is-empty';
				logArea.rows = 4;
				setLogText(_('No matching log lines.'));
				return;
			}
			logArea.className = 'cbi-input-textarea cfi-log-area';
			logArea.rows = 20;
			setLogText(filtered);
			var filteredView = logLevel.value !== 'all' || (logKeyword.value || '').trim() !== '';
			logArea.scrollTop = filteredView ? 0 : logArea.scrollHeight;
		}

		logLevel.addEventListener('change', applyLogFilter);
		logKeyword.addEventListener('input', applyLogFilter);

		function setLogError(message, error) {
			rawLogs = null;
			logArea.className = 'cbi-input-textarea cfi-log-area is-error';
			logArea.rows = 4;
			setLogText(message);
			while (logDetails.firstChild)
				logDetails.removeChild(logDetails.firstChild);
			logDetails.appendChild(E('summary', {}, _('Technical details')));
			logDetails.appendChild(E('pre', { 'class': 'cfi-log-area' }, utils.errorText(error)));
			logDetails.appendChild(utils.copyButton(utils.errorText(error)));
			logDetails.hidden = false;
		}

		function clearLogError() {
			logDetails.hidden = true;
			while (logDetails.firstChild)
				logDetails.removeChild(logDetails.firstChild);
		}

		function renderLogResult(res) {
			res = res || {};
			if (res.success !== true) {
				rawLogs = null;
				setLogError(_('Unable to read logs. Check the service status and try again.'), res.error);
			} else if (res.logs) {
				clearLogError();
				rawLogs = res.logs;
				applyLogFilter();
			} else {
				clearLogError();
				rawLogs = '';
				applyLogFilter();
			}
		}

		function refreshLogs(btn) {
			if (btn)
				utils.setBusy(btn, _('Loading...'));
			rawLogs = null;
			logArea.className = 'cbi-input-textarea cfi-log-area is-loading';
			logArea.rows = 4;
			setLogText(_('Loading...'));
			return callReadLog().then(renderLogResult).catch(function(e) {
				setLogError(_('Unable to read logs. Check the service status and try again.'), e);
			}).finally(function() {
				if (btn)
					utils.resetBusy(btn);
			});
		}

		var logBtnBar = E('div', { 'class': 'cfi-log-controls' });
		var logActions = E('div', { 'class': 'ys-actions' });
		logBtnBar.appendChild(logLevel);
		logBtnBar.appendChild(logKeyword);
		logBtnBar.appendChild(logActions);

		logActions.appendChild(E('button', {
			'class': 'cbi-button cbi-button-apply',
			'click': function() {
				return refreshLogs(this);
			}
		}, '\u21BB ' + _('Refresh')));

		logActions.appendChild(E('button', {
			'class': 'cbi-button cbi-button-reset',
			'click': function() {
				var btn = this;
				return utils.confirmAction(_('Clear Logs'), _('Clear log file?'), function() {
					utils.setBusy(btn, _('Loading...'));
					return callClearLog().then(function(res) {
						res = res || {};
						if (res.success === true) {
							rawLogs = '';
							logArea.className = 'cbi-input-textarea cfi-log-area is-empty';
							logArea.rows = 4;
							setLogText(_('Log file cleared.'));
						} else {
							utils.noticeError(_('Unable to clear logs.'), _('The previous log file was preserved.'), res.error);
						}
					}).catch(function(e) {
						utils.noticeError(_('Unable to clear logs.'), _('The previous log file was preserved.'), e);
					}).finally(function() {
						utils.resetBusy(btn);
					});
				}, _('Clear'));
			}
		}, '\u2716 ' + _('Clear Logs')));

		logSection.appendChild(logBtnBar);
		setLogText(_('Loading...'));
		logSection.appendChild(logArea);
		logSection.appendChild(logDetails);

		container.appendChild(logSection);

		/* IP History */
		var ipSection = E('div', { 'class': 'cbi-section' });
		ipSection.appendChild(E('h3', {}, _('IP History') + ' ' + _('(latest 10)')));

		var ipTableBody = E('tbody');

		function renderIpHistory(res) {
			while (ipTableBody.firstChild)
				ipTableBody.removeChild(ipTableBody.firstChild);

			res = res || {};
			if (res.success !== true) {
				ipTableBody.appendChild(E('tr', {}, E('td', { 'colspan': '2', 'data-title': _('Status') },
						utils.errorPanel(_('Unable to load IP history.'), _('Refresh and try again; the previous rows are unchanged.'), res.error)
					)));
				return;
			}

			var ips = res.ips || [];
			if (!ips.length) {
				ipTableBody.appendChild(E('tr', {}, E('td', { 'colspan': '2', 'data-title': _('Status') }, _('No IP history available'))));
				return;
			}

			ips.forEach(function(item, i) {
				var ip = (typeof item === 'string') ? item : (item.ip || '');
				ipTableBody.appendChild(E('tr', { 'class': 'tr' }, [
					E('td', { 'class': 'td', 'data-title': '#' }, String(i + 1)),
					E('td', { 'class': 'td', 'data-title': _('IP Address') }, ip)
				]));
			});
		}

		var ipBtnBar = E('div', { 'class': 'cfi-log-controls' });
		ipBtnBar.appendChild(E('button', {
			'class': 'cbi-button cbi-button-apply',
			'click': function() {
				var btn = this;
				utils.setBusy(btn, _('Loading...'));
				return callIpHistory().then(function(res) {
					renderIpHistory(res);
				}).catch(function(e) {
					renderIpHistory({ success: false, error: e.message || String(e) });
				}).finally(function() {
					utils.resetBusy(btn);
				});
			}
		}, '\u21BB ' + _('Refresh')));
		ipSection.appendChild(ipBtnBar);
		var ipHistoryStatus = E('p', { 'class': 'cbi-value-description cfi-rill-diagnostics-loading', 'role': 'status', 'aria-live': 'polite' }, _('Loading...'));
		ipSection.appendChild(ipHistoryStatus);
		function loadIpHistory() {
			ipHistoryStatus.hidden = false;
			callIpHistory().then(renderIpHistory).catch(function(e) {
				renderIpHistory({ success: false, error: e.message || String(e) });
			}).finally(function() { ipHistoryStatus.hidden = true; });
		}

		ipSection.appendChild(E('div', { 'class': 'cfi-table-scroll' }, E('table', { 'class': 'table' }, [
			E('thead', {}, E('tr', { 'class': 'tr table-titles' }, [
				E('th', { 'class': 'th' }, '#'),
				E('th', { 'class': 'th' }, _('IP Address'))
			])),
			ipTableBody
		])));
		container.appendChild(ipSection);
		if (typeof window.IntersectionObserver === 'function') {
			var ipHistoryObserver = new window.IntersectionObserver(function(entries) {
				if (entries.some(function(entry) { return entry.isIntersecting; })) {
					ipHistoryObserver.disconnect();
					loadIpHistory();
				}
			}, { threshold: 0.01 });
			ipHistoryObserver.observe(ipSection);
		} else {
			window.setTimeout(loadIpHistory, 0);
		}
		container.appendChild(intelligenceSection);

		var diagnosticsStarted = false;
		function loadRillDiagnostics() {
			if (diagnosticsStarted)
				return;
			diagnosticsStarted = true;
			diagnosticsStatus.hidden = false;
			diagnosticsContent.hidden = true;
			callRillDiagnostics().then(function(diagnostics) {
				renderDiagnostics(diagnostics);
			}).catch(function(error) {
				renderDiagnostics(null, error);
			});
		}

		function observeRillDiagnostics() {
			if (typeof window.IntersectionObserver === 'function') {
				var diagnosticsObserver = new window.IntersectionObserver(function(entries) {
					if (entries.some(function(entry) { return entry.isIntersecting; })) {
						diagnosticsObserver.disconnect();
						loadRillDiagnostics();
					}
				}, { rootMargin: '0px', threshold: 0.01 });
				diagnosticsObserver.observe(intelligenceSection);
				/* The observer may be attached after an earlier scroll already passed
				 * the section (for example while the log textarea was settling). */
				var rect = intelligenceSection.getBoundingClientRect();
				if (rect.bottom > 0 && rect.top < window.innerHeight) {
					diagnosticsObserver.disconnect();
					loadRillDiagnostics();
				}
			} else {
				/* Older browser fallback: start only when the section is in view or
				 * enters it during a scroll. */
				function loadWhenVisible() {
					var rect = intelligenceSection.getBoundingClientRect();
					if (rect.bottom > 0 && rect.top < window.innerHeight) {
						window.removeEventListener('scroll', loadWhenVisible);
						window.removeEventListener('resize', loadWhenVisible);
						loadRillDiagnostics();
					}
				}
				window.addEventListener('scroll', loadWhenVisible, { passive: true });
				window.addEventListener('resize', loadWhenVisible);
				window.setTimeout(loadWhenVisible, 0);
			}
		}
		/* Wait for the log textarea to reach its final height before observing
		 * the bottom section, so an initially short loading placeholder cannot
		 * accidentally trigger diagnostics before it is scrolled into view. */
		window.setTimeout(function() {
			refreshLogs().finally(observeRillDiagnostics);
		}, 0);

		/* The run-error notice is useful only when present. Fetch the large status
		 * payload after the log view is on screen so an optional notice cannot
		 * delay the page or the log read. */
		window.setTimeout(function() {
			utils.callStatus().then(function(status) {
				if (status && status.error && status.error !== 'Status file not found')
					logSection.appendChild(utils.errorPanel(
						_('The last service run reported an error.'),
						_('Open the log below and check the service status before retrying.'),
						status.error
					));
			}).catch(function() {});
		}, 0);

		return utils.appendFooter(container, utils.FOOTER_OPTIONS);
	}
});
