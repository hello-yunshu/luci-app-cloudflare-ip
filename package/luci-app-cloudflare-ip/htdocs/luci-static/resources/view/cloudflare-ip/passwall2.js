'use strict';
'require view';
'require ui';
'require form';
'require uci';
'require cloudflare-ip/utils as utils';

function rpcFailure(error) {
	return { _rpcError: true, error: (error && (error.message || error)) || _('Unknown') };
}

return view.extend({
	load: function() {
		return Promise.all([ uci.load('cf_ip'), utils.callCheckEnv().catch(rpcFailure) ]);
	},

	render: function(data) {
		utils.loadSharedCSS();
		var env = data[1] || {};
		if (env._rpcError || !env.passwall2_supported) {
			this.handleSave = this.handleSaveApply = this.handleReset = null;
			var message = env._rpcError ? _('Unable to check PassWall2 environment') : _('PassWall2 version is not qualified for CFI updates: %s').format(env.passwall2_version || _('not installed'));
			return utils.renderWithFooter(E('div', { 'class': 'cbi-map cfi-form-map' }, [
				E('div', { 'class': 'cbi-section' }, [
					E('h3', {}, message),
					E('p', {}, _('CFI accepts only the exact PassWall2 package version qualified by its isolated guest. No node configuration was changed.')),
					utils.technicalDetails(env.error || env.passwall2_version || '')
				])
			]), utils.FOOTER_OPTIONS);
		}

		var m = new form.Map('cf_ip', _('PassWall2'));
		var s = m.section(form.TypedSection, 'passwall2', _('PassWall2 Update Target'));
		s.anonymous = true;
		var o = s.option(form.Value, 'target_domain', _('Target Domain'));
		o.description = _('CFI parses the active global node and the complete static leaf/_shunt reference closure. It updates only one exact-matching SOCKS leaf using the top-ranked candidate. ACL roots, extra SOCKS services, chains, URLTest/balancing/interface nodes, batch nodes, unknown protocols, and invalid references fail closed.');
		o.placeholder = 'cdn.example.com';
		o.rmempty = false;
		o.datatype = 'host';

		s = m.section(form.TypedSection, 'passwall2', _('Application Behavior'));
		s.anonymous = true;
		o = s.option(form.DummyValue, '_apply_info', _('Configuration Apply'));
		o.default = _('CFI persists the selected address only. It does not call PassWall2 reload, restart, stop, or start from the transaction adapter. With stop_service disabled, an active service fails measurement before changes. If you explicitly allow a maintenance stop, CFI restores the original service before persisting the new address; service apply and target-domain egress remain unverified.');

		utils.createHandleSave(m, this);
		utils.createHandleSaveApply(m, this);
		return utils.renderWithFooter(m.render(), utils.FOOTER_OPTIONS);
	}
});
