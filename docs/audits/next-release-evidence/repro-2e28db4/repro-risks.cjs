'use strict';
if (!String.prototype.format) {
  String.prototype.format = function() {
    var args = arguments, i = 0;
    return this.replace(/%s/g, function() { return args[i++]; });
  };
}
const fs = require('fs');
const path = require('path');
const ROOT = process.env.CFIP_ROOT || process.cwd();

function textOf(node) {
  if (node == null) return '';
  if (typeof node === 'string') return node;
  if (Array.isArray(node)) return node.map(textOf).join(' ');
  return (node.children || []).map(textOf).join(' ');
}
function makeE() {
  function E(tag, attrs, children) {
    if (typeof attrs === 'string' || Array.isArray(attrs)) { children = attrs; attrs = {}; }
    const node = {
      tag, attrs: attrs || {}, children: [],
      appendChild(child) { this.children.push(child); return child; },
      get firstChild() { return this.children[0]; },
      get lastChild() { return this.children.at(-1); }
    };
    for (const child of Array.isArray(children) ? children : (children == null ? [] : [children])) node.appendChild(child);
    return node;
  }
  E.find = (node, pred, out = []) => {
    if (Array.isArray(node)) { for (const child of node) E.find(child, pred, out); return out; }
    if (!node || typeof node !== 'object') return out;
    if (pred(node)) out.push(node);
    for (const child of node.children || []) E.find(child, pred, out);
    return out;
  };
  E.findAll = (node, text) => E.find(node, n => textOf(n).trim() === text);
  return E;
}
function makeForm(E) {
  function makeOption(type, key, title, description) {
    const o = {
      type, key, title, description,
      value(v, label) { (o.values = o.values || []).push([v, label]); return o; },
      depends() { return o; }
    };
    return o;
  }
  const form = {};
  function Map(name, title, description) {
    const map = {
      name, title, description, options: {}, sections: [],
      section(kind) {
        const s = {
          kind, options: {},
          option(type, key, title2, description2) {
            const o = makeOption(type, key, title2, description2);
            s.options[key] = o; map.options[key] = o; return o;
          }
        };
        map.sections.push(s); return s;
      },
      renderContents() { return Promise.resolve(E('div', { class: 'map' }, [])); },
      render() { return this.renderContents(); }
    };
    form.lastMap = map;
    return map;
  }
  Object.assign(form, {
    Map, NamedSection: 'named', TypedSection: 'typed', GridSection: 'grid',
    Value: 'value', ListValue: 'list', Flag: 'flag', MultiValue: 'multi',
    DynamicList: 'dynamic', Button: 'button'
  });
  return form;
}
function loadView(rel, env) {
  const source = fs.readFileSync(path.join(ROOT, rel), 'utf8');
  const E = makeE();
  const form = makeForm(E);
  const rpcCalls = [];
  const rpc = {
    declare(spec) {
      return (...args) => {
        rpcCalls.push({ method: spec.method, params: args });
        const fn = env.rpc && env.rpc[spec.method];
        if (!fn) return Promise.resolve({});
        return fn(...args);
      };
    }
  };
  const notifications = [];
  const ui = {
    addNotification(kind, node) { notifications.push({ kind, text: textOf(node).trim() }); },
    showModal(title, content) { env.modal = { title, content }; },
    hideModal() { env.modal = null; }
  };
  const utils = Object.assign({
    loadSharedCSS() {},
    setBusy() {},
    resetBusy() {},
    renderWithFooter(node) { return node; },
    createHandleSave() {},
    createHandleSaveApply() {},
    FOOTER_OPTIONS: {},
    confirmAction(title, message, onConfirm, label) {
      const confirm = E('button', { class: 'cbi-button cbi-button-reset' }, label || 'Confirm');
      confirm.attrs.click = () => { ui.hideModal(); return onConfirm(); };
      const cancel = E('button', { class: 'btn' }, 'Cancel');
      env.modal = { title, content: E('div', {}, [ E('p', {}, message), confirm, cancel ]) };
      return Promise.resolve();
    }
  }, env.utils || {});
  const view = { extend(x) { return x; } };
  const factory = new Function('view', 'form', 'uci', 'rpc', 'ui', 'utils', 'E', '_', source);
  const mod = factory(view, form, { load: async () => {}, get: () => undefined }, rpc, ui, utils, E, x => x);
  return { mod, E, form, ui, utils, notifications, rpcCalls, env };
}

(async () => {
  const out = {};
  global.location = { reloadCalls: 0, reload() { global.location.reloadCalls++; } };

  // 1. OpenClash delete backup: {success:false} without error is reported as success.
  {
    const env = {
      rpc: {
        'oc-list-backups': async () => ({ success: true, backups: [{ id: 'b1', timestamp: '2026-11-03T08:00:00Z', size: 1234 }] }),
        'oc-delete-backup': async () => ({ success: false })
      },
      utils: { callCheckEnv: async () => ({ openclash_installed: true }) }
    };
    global.location.reloadCalls = 0;
    const ctx = loadView('package/luci-app-cloudflare-ip/htdocs/luci-static/resources/view/cloudflare-ip/openclash.js', env);
    const tree = await ctx.mod.render([{}, { openclash_installed: true }, { success: true, backups: [{ id: 'b1', timestamp: '2026-11-03T08:00:00Z', size: 1234 }] }]);
    const rowDelete = ctx.E.findAll(tree, 'Delete');
    out.openclash_delete = { row_delete_buttons: rowDelete.length };
    if (rowDelete.length) {
      rowDelete[0].attrs.click();
      const modalDelete = ctx.E.findAll(env.modal && env.modal.content, 'Delete');
      out.openclash_delete.modal_delete_buttons = modalDelete.length;
      if (modalDelete.length) {
        modalDelete[0].attrs.click();
        await new Promise(r => setTimeout(r, 600));
      }
    }
    out.openclash_delete.backend = { success: false };
    out.openclash_delete.notifications = ctx.notifications;
    out.openclash_delete.reload_calls = global.location.reloadCalls;
    out.openclash_delete.false_success = ctx.notifications.some(n => n.text === 'Backup deleted');
  }

  // 2. OpenClash RPC failure is classified as not-installed / no backups.
  {
    const env = {
      rpc: { 'oc-list-backups': async () => { throw new Error('ubus unavailable'); } },
      utils: { callCheckEnv: async () => { throw new Error('ubus unavailable'); } }
    };
    const ctx = loadView('package/luci-app-cloudflare-ip/htdocs/luci-static/resources/view/cloudflare-ip/openclash.js', env);
    const data = await ctx.mod.load();
    const tree = await ctx.mod.render(data);
    out.rpc_failure_openclash = { text: textOf(tree).trim(), error_visible: textOf(tree).includes('Unable to check OpenClash environment'), not_installed: textOf(tree).includes('OpenClash Not Found') };
  }

  // 2b. Sources registry/status RPC failure is collapsed to empty data.
  {
    const env = { rpc: { 'source-registry': async () => { throw new Error('ubus unavailable'); },
      'source-status': async () => { throw new Error('ubus unavailable'); } } };
    const ctx = loadView('package/luci-app-cloudflare-ip/htdocs/luci-static/resources/view/cloudflare-ip/sources.js', env);
    const data = await ctx.mod.load();
    const tree = await ctx.mod.render(data);
    out.rpc_failure_sources = { text: textOf(tree).trim().slice(0, 500), rows: ctx.E.find(tree, n => n.attrs && n.attrs['class'] === 'tr').length, error_visible: textOf(tree).includes('Unable to load source registry') };
  }

  // 2c. PassWall environment RPC failure must not be reported as not-installed.
  {
    const env = { utils: { callCheckEnv: async () => { throw new Error('ubus unavailable'); } } };
    const ctx = loadView('package/luci-app-cloudflare-ip/htdocs/luci-static/resources/view/cloudflare-ip/passwall.js', env);
    const data = await ctx.mod.load();
    const tree = await ctx.mod.render(data);
    out.rpc_failure_passwall = { text: textOf(tree).trim(), error_visible: textOf(tree).includes('Unable to check PassWall environment'), not_installed: textOf(tree).includes('PassWall Not Found') };
  }

  // 2d. Settings environment RPC failure must not claim no proxy is installed.
  {
    const env = { utils: { callCheckEnv: async () => { throw new Error('ubus unavailable'); } } };
    const ctx = loadView('package/luci-app-cloudflare-ip/htdocs/luci-static/resources/view/cloudflare-ip/settings.js', env);
    const data = await ctx.mod.load();
    await ctx.mod.render(data);
    const mode = ctx.form.lastMap.options.mode;
    out.rpc_failure_settings = { description: mode.description, error_visible: /Unable to check the proxy environment/.test(mode.description || ''), not_installed: /not installed/.test(mode.description || '') };
  }

  // 3. Sources refresh triggers reload without save; draft is discarded.
  {
    const env = {
      rpc: {
        'source-registry': async () => ({ presets: [{ id: 'cloudflare-official-v4', name: 'Cloudflare Official IPv4', group: 'official' }] }),
        'source-status': async () => ({ success: true, sources: [] }),
        'source-refresh': async () => ({ success: true })
      }
    };
    global.location.reloadCalls = 0;
    const ctx = loadView('package/luci-app-cloudflare-ip/htdocs/luci-static/resources/view/cloudflare-ip/sources.js', env);
    const tree = await ctx.mod.render([{}, { presets: [{ id: 'cloudflare-official-v4', name: 'Cloudflare Official IPv4', group: 'official' }] }, { success: true, sources: [] }]);
    const buttons = ctx.E.findAll(tree, 'Refresh Sources');
    out.sources_refresh = { buttons: buttons.length, draft_before: 'modified-but-unsaved' };
    if (buttons.length) {
      buttons[0].attrs.click();
      await new Promise(r => setTimeout(r, 600));
    }
    out.sources_refresh.notifications = ctx.notifications;
    out.sources_refresh.reload_calls = global.location.reloadCalls;
    out.sources_refresh.save_calls = 0;
    out.sources_refresh.draft_after = 'modified-but-unsaved';
  }

  // 4. Rill reset reports success but does not refresh status or generation.
  {
    const status = { intelligence: { stateGeneration: 1, state: 'disabled' } };
    const env = {
      rpc: {
        status: async () => status,
        'rill-diagnostics': async () => ({}),
        'adaptive-status': async () => ({}),
        'rill-reset': async () => ({ success: true })
      }
    };
    global.location.reloadCalls = 0;
    const ctx = loadView('package/luci-app-cloudflare-ip/htdocs/luci-static/resources/view/cloudflare-ip/intelligence.js', env);
    const data = await ctx.mod.load();
    await ctx.mod.render(data);
    const reset = ctx.form.lastMap.options._reset;
    out.rill_reset = { reset_option: !!reset, status_generation_before: status.intelligence.stateGeneration };
    if (reset && reset.onclick) {
      const button = { disabled: false, setAttribute() {}, removeAttribute() {}, getAttribute() { return null; }, textContent: 'Reset' };
      const oldConfirm = global.confirm;
      global.confirm = () => true;
      await reset.onclick({ currentTarget: button });
      global.confirm = oldConfirm;
      const confirm = ctx.E.findAll(env.modal && env.modal.content, 'Reset');
      out.rill_reset.modal_confirm_buttons = confirm.length;
      if (confirm.length) confirm[0].attrs.click();
      await new Promise(r => setTimeout(r, 600));
    }
    out.rill_reset.notifications = ctx.notifications;
    out.rill_reset.reload_calls = global.location.reloadCalls;
    out.rill_reset.status_generation_after = status.intelligence.stateGeneration;
    out.rill_reset.stale_status = status.intelligence.stateGeneration === 1 && global.location.reloadCalls === 0;
  }

  console.log(JSON.stringify(out, null, 2));
})().catch(err => { console.error(err); process.exit(1); });
