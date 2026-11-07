# Touch-emulation matrix (2026-11-07)

Device: OpenWrt `25.12.5` x86_64 Microsoft KVM (DUT), package `2.6.0-r9` at exact SHA `d1e36f3`. Method: Playwright Chromium, `viewport 1024×768`, `hasTouch=true`; 200% pass uses `640×450` with `deviceScaleFactor=2`.

## Results

- 8/8 pages PASS: overview, settings, sources, intelligence, openclash, passwall, advanced, logs. No blank/loading view, no horizontal overflow; each page had 8 controls smaller than 40×40 CSS px (LuCI native tab/menu links), listed in `touch-matrix.json`.
- Tap Refresh on overview and logs: PASS (the button accepted a tap and returned to idle).
- 3/3 at 200% PASS (overview, settings, logs), no overflow.
- Menu traversal is partial: tapping "服务" opened the top menu, but the plugin submenu entry was not reachable by a single tap in this theme (`pluginTapped=false`). Direct URLs were used for the page matrix.

## Not covered / blocked

- Physical touch panel, palm rejection, touch latency, multi-finger pinch and stylus pressure: **BLOCKED** (no touch hardware).
- Soft keyboard / IME: **BLOCKED** (headless Chromium cannot type through a real on-screen keyboard).
- Settings form controls were measured but **not tapped**, after an earlier attempt showed a "配置已保存，正在重启服务..." toast. That attempt added three explicit default options (`speedtest_dt`, `speedtest_threads`, `speedtest_ping_count`) and restarted the service. The config was restored byte-for-byte to the pre-test copy (SHA256 `2591b0cb…`), and `/etc/shadow` was restored after each login. A dropdown-tap write path is therefore a test-harness side effect, not claimed as touch evidence.

Artifacts: `touch-matrix.json`, `touch-1024-*.png`, `touch-200pct-*.png`.
