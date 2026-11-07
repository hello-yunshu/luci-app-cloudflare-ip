'use strict';
'require view';
'require ui';
'require rpc';
'require form';
'require uci';
'require cloudflare-ip/utils as utils';

var callOcListBackups = rpc.declare({ object: 'cf_ip', method: 'oc-list-backups', expect: { '': {} } });
var callOcRestoreBackup = rpc.declare({ object: 'cf_ip', method: 'oc-restore-backup', params: ['id'], expect: { '': {} } });
var callOcDeleteBackup = rpc.declare({ object: 'cf_ip', method: 'oc-delete-backup', params: ['id'], expect: { '': {} } });

function rpcFailure(error) {
	return { _rpcError: true, error: (error && (error.message || error)) || _('Unknown') };
}

function formatSize(bytes) {
	if (!bytes || bytes <= 0) return '-';
	if (bytes < 1024) return bytes + ' B';
	if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(1) + ' KB';
	return (bytes / (1024 * 1024)).toFixed(1) + ' MB';
}

function rubyRemedy(env) {
	if (env.ruby_psych === true) return null;
	if (env.ruby_status === 'ruby_missing') {
		return {
			reason: _('Ruby is not installed.'),
			action: (env.package_manager === 'apk' ? 'apk add ruby ruby-psych' : 'opkg install ruby ruby-psych')
		};
	}
	if (!env.ruby_usable) {
		return {
			reason: _('Ruby is installed but cannot run on this device (it exits with a segmentation fault).'),
			action: _('Use firmware with a working Ruby/Psych, or restore this backup on another device.')
		};
	}
	return {
		reason: _('Ruby is installed, but the Psych YAML module is missing.'),
		action: (env.package_manager === 'apk' ? 'apk add ruby-psych' : 'opkg install ruby-psych')
	};
}

return view.extend({
	title: _('OpenClash'),

	load: function() {
		return Promise.all([
			uci.load('cf_ip'),
			utils.callCheckEnv().catch(rpcFailure),
			callOcListBackups().catch(rpcFailure)
		]);
	},

	render: function(data) {
		utils.loadSharedCSS();
		var env = data[1] || {};
		var backupData = data[2] || {};

		if (env._rpcError) {
			this.handleSave = this.handleSaveApply = this.handleReset = null;
			return utils.renderWithFooter(E('div', { 'class': 'cbi-map cfi-form-map' }, [
				E('div', { 'class': 'cbi-section cfi-empty-state' }, [
					E('h3', {}, _('Unable to check OpenClash environment')),
					E('p', {}, _('Retry the environment check. If it keeps failing, open Logs & Records for the service state.')),
					utils.technicalDetails(env.error),
					E('button', { 'class': 'btn cbi-button', 'click': function() { location.reload(); } }, _('Retry'))
				])
			]), utils.FOOTER_OPTIONS);
		}

		if (!env.openclash_installed) {
			this.handleSave = this.handleSaveApply = this.handleReset = null;
			return utils.renderWithFooter(E('div', { 'class': 'cbi-map cfi-form-map' }, [
				E('div', { 'class': 'cbi-section cfi-empty-state' }, [
					E('h3', {}, _('OpenClash Not Found')),
					E('p', {}, _('OpenClash is not installed. Please install OpenClash before using this feature.'))
				])
			]), utils.FOOTER_OPTIONS);
		}

		var m = new form.Map('cf_ip', _('OpenClash'));

		var s = m.section(form.TypedSection, 'openclash', _('OpenClash Settings'));
		s.anonymous = true;

		var o;

		o = s.option(form.Value, 'config', _('Config File Path'));
		o.description = _('Path to the OpenClash YAML configuration file.');
		o.placeholder = '/etc/openclash/config/config.yaml';
		o.rmempty = false;
		o.datatype = 'string';

		o = s.option(form.Value, 'target_domain', _('Target Domain'));
		o.description = _('Only OpenClash proxies whose server matches this domain will be updated. Comma-separated for multiple domains.');
		o.placeholder = 'cdn.example.com';
		o.rmempty = false;
		o.datatype = 'string';

		o = s.option(form.Value, 'name_suffix', _('Proxy Name Suffix'));
		o.description = _('Suffix appended to the original proxy name. Placeholders: {n} = sequence number, {ip} = IP address. Leave empty to keep original names.');
		o.placeholder = ' [CF-{n}]';
		o.rmempty = true;

		o = s.option(form.Value, 'transport_filter', _('Transport Filter'));
		o.description = _('Only update proxies with the specified transport protocol. Comma-separated. Values: ws, grpc, xhttp, h2, http. Leave empty to update all supported proxies.');
		o.placeholder = 'ws,xhttp';
		o.rmempty = true;
		o.datatype = 'string';

		o = s.option(form.Value, 'backup_count', _('Backup Count'));
		o.description = _('Number of OpenClash config backups to keep.');
		o.datatype = 'range(1,20)';
		o.placeholder = '3';
		o.rmempty = false;

		utils.createHandleSave(m, this);
		utils.createHandleSaveApply(m, this);

		/* Build backup section as a separate DOM tree appended after the form */
		var backupSection = E('div', { 'class': 'cbi-section cfi-section', 'id': 'oc-backups-section' });
		backupSection.appendChild(E('h3', {}, _('Config Backups')));

		var rubyRemedyInfo = rubyRemedy(env);
		var restoreBlocked = rubyRemedyInfo !== null;
		if (restoreBlocked) {
			backupSection.appendChild(E('div', { 'class': 'alert-message warning', 'id': 'oc-ruby-warning' }, [
				E('p', {}, _('OpenClash is installed, but restoring a backup needs Ruby and the Psych YAML module.')),
				E('p', {}, rubyRemedyInfo.reason),
				E('p', {}, _('Next step: %s').format(rubyRemedyInfo.action)),
				E('p', {}, _('Backup creation, download and delete still work; only Restore is disabled.'))
			]));
		}

		var backupError = backupData._rpcError || backupData.success === false || backupData.error;
		var backups = (backupData.success === true && backupData.backups) ? backupData.backups : [];

		if (backupError) {
			backupSection.appendChild(utils.errorPanel(
				_('Unable to load OpenClash backups.'),
				_('Retry, or check that OpenClash is installed and its configuration path is valid.'),
				backupData.error || backupData._rpcError
			));
			backupSection.appendChild(E('button', { 'class': 'btn cbi-button', 'click': function() { location.reload(); } }, _('Retry')));
		} else if (backups.length === 0) {
			backupSection.appendChild(E('div', { 'class': 'cfi-empty-note' },
				_('No backups available. Backups are created automatically when the config is updated.')));
		} else {
			var headers = [_('Backup Time'), _('Size'), _('Actions')];
			var table = E('table', { 'class': 'table cfi-responsive-table' });
			var thead = E('thead');
			var headerRow = E('tr');
			headers.forEach(function(title) {
				headerRow.appendChild(E('th', {}, title));
			});
			thead.appendChild(headerRow);
			table.appendChild(thead);

			var tbody = E('tbody');

			backups.forEach(function(backup) {
				var row = E('tr');
				row.appendChild(E('td', { 'data-label': headers[0] }, backup.timestamp || backup.id || '-'));
				row.appendChild(E('td', { 'data-label': headers[1] }, formatSize(backup.size)));

				var actionsCell = E('td', { 'class': 'cfi-actions', 'data-label': headers[2] });

				actionsCell.appendChild(E('button', {
					'class': 'cbi-button cbi-button-apply',
					'disabled': restoreBlocked ? '' : null,
					'title': restoreBlocked ? rubyRemedyInfo.reason : null,
					'click': function() {
						ui.showModal(_('Confirm Restore'), [
							E('div', { 'class': 'alert-message warning' },
								_('Restore the backup from %s? A backup of the current configuration will be created first.').format(backup.timestamp || backup.id)),
							E('div', { 'class': 'right' }, [
								E('button', { 'class': 'btn', 'click': function() { ui.hideModal(); } }, _('Cancel')),
								E('button', {
									'class': 'cbi-button cbi-button-apply',
									'click': function() {
										ui.hideModal();
										ui.showModal(_('Restoring...'), [E('p', {}, _('Please wait...'))]);
										callOcRestoreBackup(backup.id).then(function(result) {
											ui.hideModal();
											if (!result || result.success !== true || result.error) {
												utils.noticeError(_('Unable to restore backup.'), _('The backup was not applied; the current configuration is unchanged.'), (result && result.error) || _('Unknown'));
											} else if (result.deferredUntilServiceStart || result.last_result === 'warning') {
												ui.addNotification(null, E('p', {}, _('Nodes updated; OpenClash is disabled and the changes will take effect after it is started')), 'warning');
												setTimeout(function() { location.reload(); }, 500);
											} else {
												ui.addNotification(null, E('p', {}, _('Backup restored successfully.')), 'info');
												setTimeout(function() { location.reload(); }, 500);
											}
										}).catch(function(e) {
											ui.hideModal();
											utils.noticeError(_('Unable to restore backup.'), _('The backup was not applied; the current configuration is unchanged.'), e);
										});
									}
								}, '\u21A9 ' + _('Restore'))
							])
						]);
					}
				}, '\u21A9 ' + _('Restore')));

				actionsCell.appendChild(E('button', {
					'class': 'cbi-button cbi-button-reset',
					'click': function() {
						ui.showModal(_('Confirm Delete'), [
							E('p', {}, _('Delete the backup from %s? This cannot be undone.').format(backup.timestamp || backup.id)),
							E('div', { 'class': 'right' }, [
								E('button', { 'class': 'btn', 'click': function() { ui.hideModal(); } }, _('Cancel')),
								E('button', {
									'class': 'cbi-button cbi-button-reset',
									'click': function() {
										ui.hideModal();
										callOcDeleteBackup(backup.id).then(function(result) {
											if (!result || result.success !== true || result.error) {
												utils.noticeError(_('Unable to delete backup.'), _('The backup file is still present.'), (result && result.error) || _('Unknown'));
											} else {
												ui.addNotification(null, E('p', {}, _('Backup deleted')), 'info');
												setTimeout(function() { location.reload(); }, 500);
											}
										}).catch(function(e) {
											utils.noticeError(_('Unable to delete backup.'), _('The backup file is still present.'), e);
										});
									}
								}, _('Delete'))
							])
						]);
					}
				}, _('Delete')));

				row.appendChild(actionsCell);
				tbody.appendChild(row);
			});

			table.appendChild(tbody);
			backupSection.appendChild(E('div', { 'class': 'cfi-table-wrap' }, table));
		}

		return utils.renderWithFooter(m.render().then(function(node) {
			/* Append backup section after the form */
			node.appendChild(backupSection);
			return node;
		}), utils.FOOTER_OPTIONS);
	}
});
