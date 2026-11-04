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
	title: _('PassWall'),

	load: function() {
		return Promise.all([
			uci.load('cf_ip'),
			utils.callCheckEnv().catch(rpcFailure)
		]);
	},

	render: function(data) {
		utils.loadSharedCSS();
		var env = data[1] || {};

		if (env._rpcError) {
			this.handleSave = this.handleSaveApply = this.handleReset = null;
			return utils.renderWithFooter(E('div', { 'class': 'cbi-map cfi-form-map' }, [
				E('div', { 'class': 'cbi-section cfi-empty-state' }, [
					E('h3', {}, _('Unable to check PassWall environment')),
					E('p', {}, _('Retry the environment check. If it keeps failing, open Logs & Records for the service state.')),
					utils.technicalDetails(env.error),
					E('button', { 'class': 'btn cbi-button', 'click': function() { location.reload(); } }, _('Retry'))
				])
			]), utils.FOOTER_OPTIONS);
		}

		if (!env.passwall_installed) {
			this.handleSave = this.handleSaveApply = this.handleReset = null;
			return utils.renderWithFooter(E('div', { 'class': 'cbi-map cfi-form-map' }, [
				E('div', { 'class': 'cbi-section cfi-empty-state' }, [
					E('h3', {}, _('PassWall Not Found')),
					E('p', {}, _('PassWall is not installed. Please install PassWall before using this feature.'))
				])
			]), utils.FOOTER_OPTIONS);
		}

		var m = new form.Map('cf_ip', _('PassWall'));

		var s = m.section(form.TypedSection, 'passwall', _('PassWall Settings'));
		s.anonymous = true;

		var o;

		o = s.option(form.Value, 'target_domain', _('Target Domain'));
		o.description = _('Only PassWall nodes whose address equals this domain will be updated. Comma-separated for multiple domains.');
		o.placeholder = 'cdn.example.com';
		o.rmempty = false;
		o.datatype = 'string';

		o = s.option(form.Value, 'name_suffix', _('Node Name Suffix'));
		o.description = _('Suffix appended to the original node name. Placeholders: {n} = sequence number, {ip} = IP address. Leave empty to keep original names.');
		o.placeholder = ' [CF-{n}]';
		o.rmempty = true;

		utils.createHandleSave(m, this);
		utils.createHandleSaveApply(m, this);

		return utils.renderWithFooter(m.render(), utils.FOOTER_OPTIONS);
	}
});
