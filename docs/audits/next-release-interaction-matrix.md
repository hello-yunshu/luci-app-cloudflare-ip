# Interaction point x seven-state matrix

Baseline SHA: `7c13b1d`. Real OpenWrt 24.10.8 + LuCI 26.205.85413 (uhttpd/rpcd/ubus), Chromium via Playwright. Every row was exercised against the live page; screenshots are `matrix/<id>-before.png` and `matrix/<id>-after.png`.

- Interaction points: **42**
- Points passing their real action + DOM/persistence assertions: **42/42**
- `default`: PASS 42, N/A 0, BLOCKED 0, FAIL 0
- `hover`: PASS 3, N/A 39, BLOCKED 0, FAIL 0
- `focus`: PASS 4, N/A 38, BLOCKED 0, FAIL 0
- `active`: PASS 11, N/A 31, BLOCKED 0, FAIL 0
- `disabled`: PASS 1, N/A 41, BLOCKED 0, FAIL 0
- `error`: PASS 4, N/A 38, BLOCKED 0, FAIL 0
- `empty`: PASS 3, N/A 39, BLOCKED 0, FAIL 0
- `open`: PASS 9, N/A 33, BLOCKED 0, FAIL 0
- Keyboard 200% (8 pages x Bootstrap/Aurora dark): **16/16 PASS**
- Per-control keyboard focus sweep (Bootstrap + Aurora dark, real Tab): **312/312 tabbed controls with a visible focus ring**, 0 failures.
- Per-control hover sweep: **298 hover events** executed without layout shift or overflow.

## Points

| ID | Page | Control | default | hover | focus | active | disabled | error | empty | open | Key assertion |
|---|---|---|---|---|---|---|---|---|---|---|---|
| ov-start | overview | Start | PASS | N/A | N/A | PASS | N/A | N/A | N/A | N/A | busy={"disabled": false, "text": "▶ Start"}; banner= |
| ov-restart | overview | Restart | PASS | N/A | N/A | PASS | N/A | N/A | N/A | N/A | text=Unable to restart service: init_action_failed

Dismiss
Overview
Settings
Candidate IP Sources
Intelligence
Advanced
Logs |
| ov-cfst | overview | Download CFST | PASS | N/A | N/A | PASS | N/A | N/A | N/A | N/A | busy=[] |
| ov-refresh-env | overview | Refresh Environment | PASS | N/A | N/A | PASS | N/A | N/A | N/A | N/A | envTable=MODE	passwall
LAST RUN TIME	-
LAST RESULT	✘ Error
BEST IPS	-
SCRIPT VERSION	2.6.0
CFST VERSION	-
GITHUB	hello-yunshu/luci-app-cloudflare-ip |
| ov-footer | overview | Footer links | PASS | PASS | PASS | N/A | N/A | N/A | N/A | PASS | hover={"outline": "3px none rgb(23, 105, 170)", "boxShadow": "none", "transform": "none", "visible": true}; focus={"outline": "2px solid rgb(23, 105, 170)", "boxShadow": "none", "transform": "none", "visible": true}; hre |
| set-enable | settings | Enable Service | PASS | N/A | PASS | N/A | N/A | N/A | N/A | N/A | toggled=true; focus={"outline": "2px solid color(srgb 0.0901961 0.411765 0.666667 / 0.3)", "boxShadow": "none", "transform": "none", "visible": true} |
| set-schedule | settings | Run Schedule | PASS | N/A | N/A | N/A | N/A | N/A | N/A | PASS | customVisible=true; customCount=1 |
| set-mode | settings | Mode | PASS | N/A | N/A | N/A | N/A | N/A | N/A | N/A | value=openclash |
| set-iptype | settings | IP Type | PASS | N/A | N/A | N/A | N/A | N/A | N/A | N/A | value=both |
| set-protocol | settings | Speed Test Protocol | PASS | N/A | N/A | N/A | N/A | N/A | N/A | N/A | value=http |
| set-validation | settings | IP Count validation | PASS | N/A | N/A | N/A | N/A | PASS | N/A | N/A | invalid=1 |
| set-save | settings | Save | PASS | N/A | N/A | PASS | N/A | N/A | N/A | N/A | changes= |
| set-apply-open | settings | Save & Apply dropdown | PASS | PASS | PASS | N/A | N/A | N/A | N/A | PASS | items=["Save & Apply", "Apply unchecked"]; open=true; closed=false |
| set-reset | settings | Reset | PASS | N/A | N/A | N/A | N/A | N/A | N/A | N/A | value=8 |
| src-budget | sources | CFST Candidate IP Count | PASS | N/A | PASS | N/A | N/A | N/A | N/A | N/A | value=256; focus={"outline": "2px solid color(srgb 0.0901961 0.411765 0.666667 / 0.3)", "boxShadow": "rgba(0, 0, 0, 0) 0px 0px 0px 0px, rgba(0, 0, 0, 0) 0px 0px 0px 0px, rgba(0, 0, 0, 0) 0px 0px 0px 0px, oklab(0 0 0 / 0) |
| src-multiselect | sources | Built-in Sources | PASS | N/A | N/A | N/A | N/A | N/A | N/A | PASS | options=22; open=true |
| src-add | sources | Add custom source | PASS | N/A | N/A | N/A | PASS | N/A | N/A | PASS | addDisabledBeforeName=true; addEnabledAfterName=true; rows=1; nameFields=0 |
| src-kind | sources | Custom source kind | PASS | N/A | N/A | N/A | N/A | N/A | N/A | PASS | editOpened=true; modalTitle=Candidate Sources - cfg06ff76; kind=manual; options=["HTTPS URL", "Manual IP list"]; manualIpVisible=2; modalInputs=4 |
| src-lan | sources | LAN Publisher | PASS | N/A | N/A | N/A | N/A | N/A | N/A | PASS | checked=true; port=12345 |
| src-refresh | sources | Refresh Sources | PASS | N/A | N/A | PASS | N/A | N/A | N/A | N/A | busy=["Add"]; draft=256; notice=Unable to refresh sources: cf-ip-auto returned no valid resultDismiss |
| src-save | sources | Save | PASS | N/A | N/A | PASS | N/A | N/A | N/A | N/A | changes= |
| int-policy | intelligence | Source Strategy | PASS | N/A | N/A | N/A | N/A | N/A | N/A | N/A | value=history-heavy |
| int-probe | intelligence | Probe Batch Size | PASS | N/A | N/A | N/A | N/A | N/A | N/A | N/A | value=4 |
| int-early | intelligence | Deterministic Early Stop | PASS | N/A | N/A | N/A | N/A | N/A | N/A | N/A | toggled=true |
| int-adaptive | intelligence | Adaptive Measurement Mode | PASS | N/A | N/A | N/A | N/A | N/A | N/A | N/A | value=guarded |
| int-rill | intelligence | Rill Runtime | PASS | N/A | N/A | N/A | N/A | N/A | N/A | N/A | enabled=true |
| int-selfcheck | intelligence | Run self-check | PASS | N/A | N/A | PASS | N/A | N/A | N/A | N/A | notice=Rill self-check fell back to Native.Dismiss; text=云云舒
 · 
Cloudflare IP Optimization
 · 
v2.6.0-r7
Project
 · 
GitHub
 · 
@云云舒
Save & Apply
▾
Save
Reset
Powered by LuCI openwrt-24.10 branch (26.205.85413~cac97ed)  |
| int-reset | intelligence | Reset learning state | PASS | PASS | N/A | N/A | N/A | N/A | N/A | PASS | modal=1; modalText=Reset Learning State

Reset Rill learning state? Native configuration will not be changed.

Cancel
Reset |
| int-long-values | intelligence | DummyValue long fields | PASS | N/A | N/A | N/A | N/A | N/A | N/A | N/A | metrics={"fields": 0, "longFields": 0, "overflow": false, "clipped": 0} |
| int-save | intelligence | Save | PASS | N/A | N/A | N/A | N/A | N/A | N/A | N/A | changes= |
| oc-path | openclash | Config File Path | PASS | N/A | N/A | N/A | N/A | N/A | PASS | N/A | value=/etc/openclash/config/config.yaml |
| oc-filter | openclash | Transport Filter | PASS | N/A | N/A | N/A | N/A | PASS | N/A | N/A | value=ws,badproto; backupAlert=1 |
| oc-backup-retry | openclash | Backup load failure / Retry | PASS | N/A | N/A | PASS | N/A | PASS | N/A | N/A | before=["Unable to load OpenClash backups: cf-ip-auto returned no valid result"]; after=["Unable to load OpenClash backups: cf-ip-auto returned no valid result"] |
| oc-save | openclash | Save | PASS | N/A | N/A | N/A | N/A | N/A | N/A | N/A | changes= |
| pw-domain | passwall | Target Domain | PASS | N/A | N/A | N/A | N/A | N/A | PASS | N/A | value=cdn.example.com |
| pw-save | passwall | Save | PASS | N/A | N/A | N/A | N/A | N/A | N/A | N/A | changes= |
| adv-mirror | advanced | GitHub Mirror | PASS | N/A | N/A | N/A | N/A | N/A | N/A | N/A | value=https://ghp.ci/ |
| adv-validation | advanced | Timeout validation | PASS | N/A | N/A | N/A | N/A | PASS | N/A | N/A | invalid=1 |
| adv-save | advanced | Save | PASS | N/A | N/A | N/A | N/A | N/A | N/A | N/A | changes= |
| log-refresh | logs | Refresh | PASS | N/A | N/A | PASS | N/A | N/A | PASS | N/A | log=No logs found.; empty=1 |
| log-clear | logs | Clear Logs | PASS | N/A | N/A | PASS | N/A | N/A | N/A | PASS | modal=Clear Logs

Clear log file?

Cancel
Clear; log=Log file cleared. |
| log-history | logs | IP History table | PASS | N/A | N/A | N/A | N/A | N/A | N/A | N/A | table=0; text=lare IP Optimization
 · 
v2.6.0-r7
Project
 · 
GitHub
 · 
@云云舒
Powered by LuCI openwrt-24.10 branch (26.205.85413~cac97ed) / OpenWrt 24.10.8 (r29233-443ec4032a) |

## Empty / uninstalled / RPC-failure evidence

`early-return/before` and `early-return/after` contain 8 screenshot pairs (OpenClash and PassWall, not-installed and RPC-failure, 1280/375). Before: no shared CSS, no footer, transparent background and 0 radius. After: shared CSS loaded, card styled, footer present, description and Retry visible.

OpenClash and PassWall RPC-failure/not-installed states are `PASS` evidence for the `empty` and `error` columns above. Logs empty state is exercised by `log-clear`.

## BLOCKED / not exercised

- Physical router hardware and 24h soak: **NOT RUN** (container evidence only).
- OpenClash restore/delete backup actions: **BLOCKED** — no backup files exist in the disposable container; only the backup load-failure + Retry state is reachable. Reason recorded, no fake fixture used.
- Speed-test log modal: **BLOCKED** — only opens while `last_result=running`; the container has no CFST binary/network, so the running state could not be produced. The `Describe`/`Download CFST` active state is covered instead.

Programmatic source: `matrix.json` (42 point records), `keyboard-200.json`, `focus-sweep.json`, `early-return/{before,after}/metrics.json`. Counts above are generated from those files, not hand-edited.
