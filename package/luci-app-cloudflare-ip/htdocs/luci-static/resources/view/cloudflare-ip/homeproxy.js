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
		if (env._rpcError || !env.homeproxy_supported) {
			this.handleSave = this.handleSaveApply = this.handleReset = null;
			var message = env._rpcError ? _('Unable to check HomeProxy environment') : _('HomeProxy version is not qualified for CFI updates: %s').format(env.homeproxy_version || _('not installed'));
			return utils.renderWithFooter(E('div', { 'class': 'cbi-map cfi-form-map' }, [
				E('div', { 'class': 'cbi-section' }, [
					E('h3', {}, message),
					E('p', {}, _('CFI only accepts the exact HomeProxy package version qualified by its isolated runtime test. No node configuration was changed.')),
					utils.technicalDetails(env.error || env.homeproxy_version || '')
				])
			]), utils.FOOTER_OPTIONS);
		}

		var m = new form.Map('cf_ip', _('HomeProxy'));
		var s = m.section(form.TypedSection, 'homeproxy', _('HomeProxy Update Target'));
		s.anonymous = true;
		var o = s.option(form.Value, 'target_domain', _('Target Domain'));
		o.description = _('Only the active ordinary SOCKS main_node whose address exactly matches this hostname is eligible. CFI writes only the top-ranked candidate to that one existing node; it never creates or copies nodes. The HomeProxy version and simple routing roles are checked again before every write.');
		o.placeholder = 'cdn.example.com';
		o.rmempty = false;
		o.datatype = 'host';

		s = m.section(form.TypedSection, 'homeproxy', _('Application Behavior'));
		s.anonymous = true;
		o = s.option(form.DummyValue, '_apply_info', _('Configuration Apply'));
		o.default = _('CFI persists the node address only. With stop_service disabled, an active HomeProxy is not stopped and the update remains pending. If you explicitly enable the maintenance stop in Settings, CFI restores HomeProxy after measurement; service startup is recorded, but target-domain egress is still unverified. No hard restart fallback is used.');

		utils.createHandleSave(m, this);
		utils.createHandleSaveApply(m, this);
		return utils.renderWithFooter(m.render(), utils.FOOTER_OPTIONS);
	}
});
