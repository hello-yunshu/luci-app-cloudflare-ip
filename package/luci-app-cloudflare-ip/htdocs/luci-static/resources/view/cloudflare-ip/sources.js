'use strict';
'require view';
'require form';
'require uci';
'require rpc';
'require ui';
'require cloudflare-ip/utils as utils';

var callRegistry = rpc.declare({object:'cf_ip', method:'source-registry', expect:{'':{}}});
var callStatus = rpc.declare({object:'cf_ip', method:'source-status', expect:{'':{}}});
var callRefresh = rpc.declare({object:'cf_ip', method:'source-refresh', expect:{'':{}}});

function rpcFailure(error) {
  return { _rpcError: true, error: (error && (error.message || error)) || _('Unknown') };
}

function statusMap(rows) {
  var out={}; (rows||[]).forEach(function(x){ out[x.id]=x; }); return out;
}

function stateTone(entry) {
  if (entry && entry.success === true)
    return entry.stale ? 'orange' : 'green';
  if (entry && entry.lastError)
    return 'red';
  return 'gray';
}

function stateBadge(entry, label) {
  var tone = ({ green:'success', red:'important', orange:'warning', gray:'' })[stateTone(entry)] || '';
  return E('span',{ 'class':('label ' + tone).trim() },label);
}

return view.extend({
  load:function(){ return Promise.all([uci.load('cf_ip'),callRegistry().catch(rpcFailure),callStatus().catch(rpcFailure)]); },
  render:function(data){
    utils.loadSharedCSS();
    var regData=data[1]||{}, stData=data[2]||{}, reg=regData.presets||[], st=statusMap(stData.sources||[]), m=new form.Map('cf_ip',_('Candidate Sources')),s,o;
    if (regData._rpcError)
      return utils.renderWithFooter(E('div',{'class':'cbi-map cfi-form-map'}, E('div',{'class':'cbi-section'},[
        E('h3',{},_('Unable to load source registry')),
        E('p',{},_('Retry the source registry check. If it keeps failing, open Logs & Records.')),
        utils.technicalDetails(regData.error),
        E('button',{'class':'btn cbi-button','click':function(){location.reload();}},_('Retry'))
      ])), utils.FOOTER_OPTIONS);
    s=m.section(form.TypedSection,'service',_('Candidate Budget'));
    s.anonymous=true;
    o=s.option(form.Value,'candidate_budget',_('CFST Candidate IP Count'),_('Maximum unique IPs supplied to one CFST run. Allocation is automatic: a small local-history share, a majority community share, and the remainder official-range exploration; unused quota flows to the other pools.'));
    o.datatype='range(100,512)'; o.default='128'; o.rmempty=false;
    o=s.option(form.MultiValue,'builtin_sources',_('Built-in Sources'),_('Official sources are authoritative ranges. Community sources are untrusted seed IPs and are always re-tested locally.'));
    reg.forEach(function(x){
      var group=x.group==='official'?_('Official'):x.group==='carrier'?_('Carrier-specific'):x.group==='measured'?_('Measured Seeds'):_('Recommended Community');
      o.value(x.id, x.group==='official' ? x.name : group+' · '+x.name);
    });
    o.rmempty=false;

    s=m.section(form.GridSection,'source',_('Custom Sources'),_('Custom sources accept HTTPS text lists containing IP, IP:port, IPv6, bracketed IPv6:port, or CIDR. Only the IP/CIDR is retained; domains are rejected.'));
    s.addremove=true; s.anonymous=false;
    o=s.option(form.Flag,'enabled',_('Enabled')); o.default='1'; o.rmempty=false;
    o=s.option(form.Value,'name',_('Name')); o.rmempty=false;
    o=s.option(form.ListValue,'kind',_('Kind')); o.value('url',_('HTTPS URL')); o.value('manual',_('Manual IP list')); o.default='url';
    o=s.option(form.Value,'url',_('URL')); o.depends('kind','url'); o.placeholder='https://example.com/ip.txt';
    o=s.option(form.DynamicList,'ip',_('Manual IP / CIDR')); o.depends('kind','manual');
    o=s.option(form.ListValue,'family',_('Family')); o.value('auto',_('Auto')); o.value('ipv4','IPv4'); o.value('ipv6','IPv6'); o.default='auto';

    s=m.section(form.TypedSection,'lan',_('LAN Result Publisher'),_('Optional compatibility output for other LAN tools. PassWall/OpenClash still use direct modification and do not need this.'));
    s.anonymous=true;
    o=s.option(form.Flag,'enabled',_('Enable LAN Publisher'));o.default='0';o.rmempty=false;
    o=s.option(form.Value,'bind_address',_('Bind IPv4'),_('Leave empty to use the current LAN IPv4 automatically. Public or 0.0.0.0 bindings are refused.'));o.placeholder=_('LAN auto-detect');
    o=s.option(form.Value,'port',_('HTTP Port'));o.datatype='range(1024,65535)';o.default='12345';
    o=s.option(form.DummyValue,'_paths',_('Published Paths'));o.cfgvalue=function(){return '/ip.txt · /best-ipv4.txt · /best-ipv6.txt · /result.json';};

    var tableBody=E('tbody');
    var box=E('div',{'class':'cbi-section'},[
      E('h3',{},_('Runtime Source Status')),
      E('p',{},_('Each run allocates roughly 1/8 to fresh history champions, 5/8 to community seeds, and 1/4 to Cloudflare official range exploration. Missing pools flow to other sources. All candidates are deduplicated and measured locally in one CFST run; community ports are never reused.')),
      E('div',{'class':'cfi-table-scroll'},E('table',{'class':'table'},[
        E('thead',{},E('tr',{},[
          E('th',{},_('Source')),
          E('th',{},_('State')),
          E('th',{},_('Candidates')),
          E('th',{},_('Last Error'))
        ])),
        tableBody
      ]))
    ]);
    if (stData._rpcError)
      box.appendChild(utils.errorPanel(_('Unable to load source status.'), _('Retry the page; the source rows below are unavailable until the RPC succeeds.'), stData.error));
    var seen={};
    if (!stData._rpcError) {
      reg.forEach(function(x){ var q=st[x.id]||{}, state=q._rpcError?utils.sourceStateLabel(q):(q.success===true?utils.sourceStateLabel(q):_('Not fetched')); seen[x.id]=true; tableBody.appendChild(E('tr',{'class':'tr'},[
        E('td',{'class':'td','data-title':_('Source')},x.name),
        E('td',{'class':'td','data-title':_('State')},stateBadge(q,state)),
        E('td',{'class':'td','data-title':_('Candidates')},String(q.parsedCount||0)),
        E('td',{'class':'td','data-title':_('Last Error')},utils.sourceErrorNode(q.lastError))
      ])); });
      Object.keys(st).filter(function(id){return !seen[id];}).sort().forEach(function(id){var q=st[id],state=q.success===true?utils.sourceStateLabel(q):_('Error');tableBody.appendChild(E('tr',{'class':'tr'},[
        E('td',{'class':'td','data-title':_('Source')},id),
        E('td',{'class':'td','data-title':_('State')},q.success===true?stateBadge(q,state):E('span',{'class':'label important'},state)),
        E('td',{'class':'td','data-title':_('Candidates')},String(q.parsedCount||0)),
        E('td',{'class':'td','data-title':_('Last Error')},utils.sourceErrorNode(q.lastError))
      ]));});
    }
    box.appendChild(E('button',{'class':'btn cbi-button-action','click':function(){var btn=this;utils.setBusy(btn,_('Refreshing...'));return callRefresh().then(function(r){if(r&&r.success===true){ui.addNotification(null,E('p',{},_('Sources refreshed; candidate pool prepared. Unsaved edits were kept.')),'info');}else{utils.noticeError(_('Unable to refresh sources.'), _('The previous candidate pool is unchanged; unsaved edits are still kept.'), (r&&r.error)||_('Unknown'));}}).catch(function(e){utils.noticeError(_('Unable to refresh sources.'), _('The previous candidate pool is unchanged; unsaved edits are still kept.'), e);}).finally(function(){utils.resetBusy(btn);});}},_('Refresh Sources')));
    utils.createHandleSave(m, this);
    utils.createHandleSaveApply(m, this);
    // Map.save() renders again before validation. Keep runtime controls on that render too.
    var renderMap=m.renderContents.bind(m);
    m.renderContents=function(){ return utils.renderWithFooter(renderMap().then(function(node){
      node.appendChild(box);
      /* 空表的占位行由 form.GridSection 生成，只有一个没有 data-title 的 td；
       * 补上标签，窄屏堆叠时才不会出现无标题的空单元格。 */
      node.querySelectorAll('.cbi-section-table-row.placeholder > td.td').forEach(function(td){
        if (!td.getAttribute('data-title')) td.setAttribute('data-title', _('Status'));
      });
      /* 主题的 GridSection 只给除首列/操作列外的单元格加 data-title，
       * 首列（来源名）与操作列在窄屏堆叠时缺标签，这里按表头补齐。 */
      node.querySelectorAll('table.cbi-section-table').forEach(function(table){
        /* 8 列的来源表在 360/600 下宽约 590px，裸放会把文档撑开；
         * 套一层滚动容器，窄屏可横向滑动而不影响页面宽度。 */
        if (!table.parentNode || !table.parentNode.classList.contains('cfi-table-scroll')) {
          var wrap = E('div', { 'class': 'cfi-table-scroll' });
          table.parentNode.insertBefore(wrap, table);
          wrap.appendChild(table);
        }
        var heads = Array.prototype.map.call(table.querySelectorAll('thead th'), function(th){
          return (th.textContent || '').trim();
        });
        table.querySelectorAll('tbody tr').forEach(function(tr){
          Array.prototype.forEach.call(tr.children, function(td, i){
            if (!td.classList.contains('td') || td.getAttribute('data-title')) return;
            td.setAttribute('data-title', heads[i] || (i === heads.length - 1 ? _('Actions') : _('Value')));
          });
        });
      });
      return node;
    }), utils.FOOTER_OPTIONS); };
    return m.render();
  }
});
