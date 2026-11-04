# Interaction matrix - seven-state candidate matrix

> 当前候选：`90dfc13`。本轮新建的 51 点七态矩阵在 `phase-f/matrix/matrix.json`，报告见 `next-release-phase-f-report.md`；下文的 43 点旧矩阵保留为阶段 C/refinement 历史证据。

Baseline SHA: `9adb2d5` for the corrected points; the remaining points were exercised at `7c13b1d`, and the only later code change was the stat-card radius override, which does not alter control behavior. Evidence was re-opened and corrected after the fresh-eyes audit.

- Checks: **43** = **41 interactive points + 2 read-only content checks**.
- Pass: **43/43**; FAIL: 0.
- `default`: PASS 43, N/A 0, BLOCKED 0, FAIL 0
- `hover`: PASS 3, N/A 40, BLOCKED 0, FAIL 0
- `focus`: PASS 4, N/A 39, BLOCKED 0, FAIL 0
- `active`: PASS 12, N/A 31, BLOCKED 0, FAIL 0
- `disabled`: PASS 1, N/A 42, BLOCKED 0, FAIL 0
- `error`: PASS 4, N/A 39, BLOCKED 0, FAIL 0
- `empty`: PASS 3, N/A 40, BLOCKED 0, FAIL 0
- `open`: PASS 10, N/A 33, BLOCKED 0, FAIL 0
- Per-control real Tab focus sweep: **312/312 PASS**, 0 failures; hover events: 298.
- Keyboard 200%: **16/16 PASS**.

## Audit corrections

- `log-history` and `int-long-values` had no actionable control; reclassified as read-only content checks (2 of 43).
- `ov-cfst`: before/after were identical; re-ran with a real `download-cfst` RPC, disabled `Downloading...` state, notification and distinct screenshot.
- `oc-backup-retry`: before/after were identical; a controlled backend fixture failed the first listing, Retry re-queried and rendered the backup table (error -> table transition).
- Six Save points previously asserted only empty server `uci changes`; re-ran with browser UCI staging value + `changes=1` assertions. Added `set-apply` with real Save & Apply and server readback (`ip_count=8`).
- `int-long-values` had sampled a Loading view (fields=0); re-ran after view load: 57 fields, 5 long, 0 clipped, no overflow.

## Points

| ID | Kind | Page | Control | default | hover | focus | active | disabled | error | empty | open | Key assertion |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ov-start | interactive | overview | Start | PASS | N/A | N/A | PASS | N/A | N/A | N/A | N/A | busy={"disabled": false, "text": "▶ Start"}; banner= |
| ov-restart | interactive | overview | Restart | PASS | N/A | N/A | PASS | N/A | N/A | N/A | N/A | text=Unable to restart service: init_action_failed

Dismiss
Overview
Settings
Candidate IP Sources
Intelligence
Advanced
Logs |
| ov-cfst | interactive | overview | Download CFST | PASS | N/A | N/A | PASS | N/A | N/A | N/A | N/A | busy={"text": "Downloading...", "disabled": true}; notice=Downloading CFST, please wait...; rpc=cf_ip.download-cfst via /ubus; beforeBytes=75919; afterBytes=78731 |
| ov-refresh-env | interactive | overview | Refresh Environment | PASS | N/A | N/A | PASS | N/A | N/A | N/A | N/A | envTable=MODE	passwall
LAST RUN TIME	-
LAST RESULT	✘ Error
BEST IPS	-
SCRIPT VERSION	2.6.0
CFST VERSION	-
GITHUB	hello-yunshu/luci-app-cloudflare-ip |
| ov-footer | interactive | overview | Footer links | PASS | PASS | PASS | N/A | N/A | N/A | N/A | PASS | hover={"outline": "3px none rgb(23, 105, 170)", "boxShadow": "none", "transform": "none", "visible": true}; focus={"outline": "2px solid rgb(23, 105, 170)", "boxShadow": "none", "transform": "none", " |
| set-enable | interactive | settings | Enable Service | PASS | N/A | PASS | N/A | N/A | N/A | N/A | N/A | toggled=true; focus={"outline": "2px solid color(srgb 0.0901961 0.411765 0.666667 / 0.3)", "boxShadow": "none", "transform": "none", "visible": true} |
| set-schedule | interactive | settings | Run Schedule | PASS | N/A | N/A | N/A | N/A | N/A | N/A | PASS | customVisible=true; customCount=1 |
| set-mode | interactive | settings | Mode | PASS | N/A | N/A | N/A | N/A | N/A | N/A | N/A | value=openclash |
| set-iptype | interactive | settings | IP Type | PASS | N/A | N/A | N/A | N/A | N/A | N/A | N/A | value=both |
| set-protocol | interactive | settings | Speed Test Protocol | PASS | N/A | N/A | N/A | N/A | N/A | N/A | N/A | value=http |
| set-validation | interactive | settings | IP Count validation | PASS | N/A | N/A | N/A | N/A | PASS | N/A | N/A | invalid=1 |
| set-save | interactive | settings | Save | PASS | N/A | N/A | PASS | N/A | N/A | N/A | N/A | browserValue=16; changes=1; formValue=16 |
| set-apply-open | interactive | settings | Save & Apply dropdown | PASS | PASS | PASS | N/A | N/A | N/A | N/A | PASS | items=["Save & Apply", "Apply unchecked"]; open=true; closed=false |
| set-reset | interactive | settings | Reset | PASS | N/A | N/A | N/A | N/A | N/A | N/A | N/A | value=8 |
| src-budget | interactive | sources | CFST Candidate IP Count | PASS | N/A | PASS | N/A | N/A | N/A | N/A | N/A | value=256; focus={"outline": "2px solid color(srgb 0.0901961 0.411765 0.666667 / 0.3)", "boxShadow": "rgba(0, 0, 0, 0) 0px 0px 0px 0px, rgba(0, 0, 0, 0) 0px 0px 0px 0px, rgba(0, 0, 0, 0) 0px 0px 0px 0 |
| src-multiselect | interactive | sources | Built-in Sources | PASS | N/A | N/A | N/A | N/A | N/A | N/A | PASS | options=22; open=true |
| src-add | interactive | sources | Add custom source | PASS | N/A | N/A | N/A | PASS | N/A | N/A | PASS | addDisabledBeforeName=true; addEnabledAfterName=true; rows=1; nameFields=0 |
| src-kind | interactive | sources | Custom source kind | PASS | N/A | N/A | N/A | N/A | N/A | N/A | PASS | editOpened=true; modalTitle=Candidate Sources - cfg06ff76; kind=manual; options=["HTTPS URL", "Manual IP list"]; manualIpVisible=2; modalInputs=4 |
| src-lan | interactive | sources | LAN Publisher | PASS | N/A | N/A | N/A | N/A | N/A | N/A | PASS | checked=true; port=12345 |
| src-refresh | interactive | sources | Refresh Sources | PASS | N/A | N/A | PASS | N/A | N/A | N/A | N/A | busy=["Add"]; draft=256; notice=Unable to refresh sources: cf-ip-auto returned no valid resultDismiss |
| src-save | interactive | sources | Save | PASS | N/A | N/A | PASS | N/A | N/A | N/A | N/A | browserValue=256; changes=1; formValue=256 |
| int-policy | interactive | intelligence | Source Strategy | PASS | N/A | N/A | N/A | N/A | N/A | N/A | N/A | value=history-heavy |
| int-probe | interactive | intelligence | Probe Batch Size | PASS | N/A | N/A | N/A | N/A | N/A | N/A | N/A | value=4 |
| int-early | interactive | intelligence | Deterministic Early Stop | PASS | N/A | N/A | N/A | N/A | N/A | N/A | N/A | toggled=true |
| int-adaptive | interactive | intelligence | Adaptive Measurement Mode | PASS | N/A | N/A | N/A | N/A | N/A | N/A | N/A | value=guarded |
| int-rill | interactive | intelligence | Rill Runtime | PASS | N/A | N/A | N/A | N/A | N/A | N/A | N/A | enabled=true |
| int-selfcheck | interactive | intelligence | Run self-check | PASS | N/A | N/A | PASS | N/A | N/A | N/A | N/A | notice=Rill self-check fell back to Native.Dismiss; text=云云舒
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
Powered by LuCI openwrt-24.10 branch (26 |
| int-reset | interactive | intelligence | Reset learning state | PASS | PASS | N/A | N/A | N/A | N/A | N/A | PASS | modal=1; modalText=Reset Learning State

Reset Rill learning state? Native configuration will not be changed.

Cancel
Reset |
| int-long-values | read-only | intelligence | DummyValue long fields | PASS | N/A | N/A | N/A | N/A | N/A | N/A | N/A | fields=57; longFields=5; overflow=false; clipped=0 |
| int-save | interactive | intelligence | Save | PASS | N/A | N/A | N/A | N/A | N/A | N/A | N/A | browserValue=5; changes=1; formValue=5 |
| oc-path | interactive | openclash | Config File Path | PASS | N/A | N/A | N/A | N/A | N/A | PASS | N/A | value=/etc/openclash/config/config.yaml |
| oc-filter | interactive | openclash | Transport Filter | PASS | N/A | N/A | N/A | N/A | PASS | N/A | N/A | value=ws,badproto; backupAlert=1 |
| oc-backup-retry | interactive | openclash | Backup load failure / Retry | PASS | N/A | N/A | PASS | N/A | PASS | N/A | N/A | alertBefore=Unable to load OpenClash backups: fixture: backup listing unavailable; alertAfter=[]; tableRowsAfterRetry=1; note=controlled fixture failed the first listing; Retry re-queried and rendered |
| oc-save | interactive | openclash | Save | PASS | N/A | N/A | N/A | N/A | N/A | N/A | N/A | browserValue=3; changes=1; formValue=3 |
| pw-domain | interactive | passwall | Target Domain | PASS | N/A | N/A | N/A | N/A | N/A | PASS | N/A | value=cdn.example.com |
| pw-save | interactive | passwall | Save | PASS | N/A | N/A | N/A | N/A | N/A | N/A | N/A | browserValue= [CF-{n}]; changes=1; formValue= [CF-{n}] |
| adv-mirror | interactive | advanced | GitHub Mirror | PASS | N/A | N/A | N/A | N/A | N/A | N/A | N/A | value=https://ghp.ci/ |
| adv-validation | interactive | advanced | Timeout validation | PASS | N/A | N/A | N/A | N/A | PASS | N/A | N/A | invalid=1 |
| adv-save | interactive | advanced | Save | PASS | N/A | N/A | N/A | N/A | N/A | N/A | N/A | browserValue=3; changes=1; formValue=3 |
| log-refresh | interactive | logs | Refresh | PASS | N/A | N/A | PASS | N/A | N/A | PASS | N/A | log=No logs found.; empty=1 |
| log-clear | interactive | logs | Clear Logs | PASS | N/A | N/A | PASS | N/A | N/A | N/A | PASS | modal=Clear Logs

Clear log file?

Cancel
Clear; log=Log file cleared. |
| log-history | read-only | logs | IP History table | PASS | N/A | N/A | N/A | N/A | N/A | N/A | N/A | table=0; text=lare IP Optimization
 · 
v2.6.0-r7
Project
 · 
GitHub
 · 
@云云舒
Powered by LuCI openwrt-24.10 branch (26.205.85413~cac97ed) / OpenWrt 24.10.8 (r29233-443ec4032a) |
| set-apply | interactive | settings | Save & Apply | PASS | N/A | N/A | PASS | N/A | N/A | N/A | PASS | serverValue=8; formValue=8 |

Programmatic source: `matrix/matrix.json` (43 records), `keyboard-200/keyboard-200.json`, `focus-sweep/focus-sweep.json`. Counts are generated from JSON.
