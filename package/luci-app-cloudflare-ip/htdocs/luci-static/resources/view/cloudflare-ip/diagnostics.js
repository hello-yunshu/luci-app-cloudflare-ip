'use strict';
'require view';
'require ui';
'require rpc';
'require cloudflare-ip/utils as utils';

var callReadLog = rpc.declare({ object: 'cf_ip', method: 'read-log', expect: { '': {} } });
var callClearLog = rpc.declare({ object: 'cf_ip', method: 'clear-log', expect: { '': {} } });
var callIpHistory = rpc.declare({ object: 'cf_ip', method: 'ip-history', expect: { '': {} } });
var callRillDiagnostics = rpc.declare({ object: 'cf_ip', method: 'rill-diagnostics', expect: { '': {} } });

var css = `
	.cfi-ip-table {
		width: 100%;
	}
	.cfi-table-wrap > .cfi-ip-table {
		min-width: 0;
	}
	.cfi-ip-table th:first-child,
	.cfi-ip-table td:first-child {
		width: 3em;
		text-align: center;
	}
	.cfi-ip-table td {
		font-family: monospace;
		word-break: break-all;
	}
	@media (max-width: 600px) {
		.cfi-ip-table td {
			font-size: 0.85em;
		}
	}
`;

return view.extend({
	/* Actions use their own RPC controls; this view has no editable UCI map. */
	handleSave: null,
	handleSaveApply: null,
	handleReset: null,

	load: function() {
		return Promise.all([
			utils.callStatus().catch(function() { return {}; }),
			callIpHistory().catch(function() { return { success: false, ips: [] }; }),
			callRillDiagnostics().catch(function() { return { success: false, error: _('Diagnostics unavailable') }; })
		]).then(function(results) {
			return {
				status: results[0],
				historyData: results[1],
				diagnostics: results[2]
			};
		});
	},

	render: function(data) {
		utils.loadSharedCSS();
		var status = data.status || {};
		var historyData = data.historyData || {};
		var diagnostics = data.diagnostics || {};

		var container = E('div', { 'class': 'cbi-map cfi-dashboard' });
		container.appendChild(E('style', {}, css));

		container.appendChild(E('h2', { 'class': 'cbi-map-title' }, _('Logs & Records')));

		var intelligenceSection = E('div', { 'class': 'cbi-section cfi-section' });
		intelligenceSection.appendChild(E('h3', {}, _('Rill Diagnostics')));
		intelligenceSection.appendChild(E('p', {}, _('This snapshot explains fallback, qualification, delayed feedback, Prefix and Colo intelligence without exposing the internal model.')));
		intelligenceSection.appendChild(E('p', { 'class': 'cfi-inline-link' },
			E('a', { 'class': 'cbi-button cfi-link-button', 'href': L.url('admin/services/cf_ip/intelligence') }, _('Open Intelligence'))));
		if (diagnostics.success !== true) {
			intelligenceSection.appendChild(E('div', { 'class': 'alert-message danger', 'role': 'alert' }, [
				E('p', {}, _('Diagnostics unavailable. Refresh the page or check the service status, then try again.')),
				E('details', {}, [
					E('summary', {}, _('Technical details')),
					E('pre', { 'class': 'cfi-log-area', 'style': 'white-space:pre-wrap;max-height:12em;overflow:auto;margin:0.5em 0 0' }, diagnostics.error || _('Unknown'))
				])
			]));
		} else {
			var diagnosticsPre = E('pre', { 'class': 'cfi-log-area', 'style': 'white-space:pre-wrap;max-height:28em;overflow:auto' }, JSON.stringify({
				runtime: diagnostics.runtime || {},
				qualification: diagnostics.qualification || {},
				sourcePolicy: diagnostics.sourcePolicy || {},
				reusePolicy: diagnostics.reusePolicy || {},
				prefixIntelligence: diagnostics.prefixIntelligence || {},
				coloIntelligence: diagnostics.coloIntelligence || {},
				pendingFeedback: diagnostics.pendingFeedback || [],
				stateMeta: diagnostics.stateMeta || {}
			}, null, 2));
			intelligenceSection.appendChild(diagnosticsPre);
		}
		container.appendChild(intelligenceSection);

		/* Recent Logs */
		var logSection = E('div', { 'class': 'cbi-section cfi-section' });
		logSection.appendChild(E('h3', {}, _('Recent Logs')));

		var logArea = E('textarea', {
			'class': 'cbi-input-textarea cfi-log-area is-loading',
			'id': 'log-area',
			'rows': 20,
			'readonly': 'readonly'
		}, '');
		var logDetails = E('details', { 'class': 'cfi-error-details', 'hidden': true });

		function setLogText(text) {
			logArea.value = text;
		}

		function setLogError(message, error) {
			logArea.className = 'cbi-input-textarea cfi-log-area is-error';
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
				setLogError(_('Unable to read logs. Check the service status and try again.'), res.error);
			} else if (res.logs) {
				clearLogError();
				logArea.className = 'cbi-input-textarea cfi-log-area';
				setLogText(res.logs);
				if (!res.logs.trim())
					logArea.className = 'cbi-input-textarea cfi-log-area is-empty';
				else
					logArea.scrollTop = logArea.scrollHeight;
			} else {
				clearLogError();
				logArea.className = 'cbi-input-textarea cfi-log-area is-empty';
				setLogText(_('No logs found.'));
			}
		}

		function refreshLogs(btn) {
			if (btn)
				utils.setBusy(btn, _('Loading...'));
			logArea.className = 'cbi-input-textarea cfi-log-area is-loading';
			setLogText(_('Loading...'));
			return callReadLog().then(renderLogResult).catch(function(e) {
				setLogError(_('Unable to read logs. Check the service status and try again.'), e);
			}).finally(function() {
				if (btn)
					utils.resetBusy(btn);
			});
		}

		var logBtnBar = E('div', { 'class': 'cfi-btn-group', 'style': 'margin-bottom:1em' });

		logBtnBar.appendChild(E('button', {
			'class': 'cbi-button cbi-button-apply',
			'click': function() {
				return refreshLogs(this);
			}
		}, '\u21BB ' + _('Refresh')));

		logBtnBar.appendChild(E('button', {
			'class': 'cbi-button cbi-button-reset',
			'click': function() {
				var btn = this;
				return utils.confirmAction(_('Clear Logs'), _('Clear log file?'), function() {
					utils.setBusy(btn, _('Loading...'));
					return callClearLog().then(function(res) {
						res = res || {};
						if (res.success === true) {
							logArea.className = 'cbi-input-textarea cfi-log-area is-empty';
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
		window.setTimeout(refreshLogs, 0);

		if (status.error && status.error !== 'Status file not found') {
			logSection.appendChild(utils.errorPanel(
				_('The last service run reported an error.'),
				_('Open the log below and check the service status before retrying.'),
				status.error
			));
		}
		container.appendChild(logSection);

		/* IP History */
		var ipSection = E('div', { 'class': 'cbi-section cfi-section' });
		ipSection.appendChild(E('h3', {}, _('IP History') + ' ' + _('(latest 10)')));

		var ipTableBody = E('tbody');

		function renderIpHistory(res) {
			while (ipTableBody.firstChild)
				ipTableBody.removeChild(ipTableBody.firstChild);

			res = res || {};
			if (res.success !== true) {
				ipTableBody.appendChild(E('tr', { 'class': 'tr' }, E('td', { 'class': 'td', 'colspan': '2' },
						utils.errorPanel(_('Unable to load IP history.'), _('Refresh and try again; the previous rows are unchanged.'), res.error)
					)));
				return;
			}

			var ips = res.ips || [];
			if (!ips.length) {
				ipTableBody.appendChild(E('tr', { 'class': 'tr cfi-no-hover' }, E('td', { 'class': 'td', 'colspan': '2', 'style': 'color:var(--subtext-color);font-style:italic' }, _('No IP history available'))));
				return;
			}

			ips.forEach(function(item, i) {
				var ip = (typeof item === 'string') ? item : (item.ip || '');
				ipTableBody.appendChild(E('tr', { 'class': 'tr' }, [
					E('td', { 'class': 'td' }, String(i + 1)),
					E('td', { 'class': 'td' }, ip)
				]));
			});
		}

		var ipBtnBar = E('div', { 'class': 'cfi-btn-group', 'style': 'margin-bottom:1em' });
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

		renderIpHistory(historyData);

		ipSection.appendChild(E('div', { 'class': 'cfi-table-wrap' }, E('table', { 'class': 'table cfi-ip-table' }, [
			E('thead', {}, E('tr', { 'class': 'tr' }, [
				E('th', { 'class': 'th' }, '#'),
				E('th', { 'class': 'th' }, _('IP Address'))
			])),
			ipTableBody
		])));
		container.appendChild(ipSection);

		return utils.appendFooter(container, utils.FOOTER_OPTIONS);
	}
});
