# OpenClash restore + Ruby/Psych precheck (2026-11-04)

结论：**PASS（真实恢复成功 + 三态前置检查）**。真实恢复在 OpenWrt 24.10.8 `armsr/armv8`（aarch64）容器、真实 mihomo 1.19.33 控制器、真实 LuCI/rpcd 上完成。x86_64 在 Apple Silicon 的 Rosetta 仿真下 `ruby -v` 仍为 rc 139；该环境类明确不可用，不属于缺库或扩展问题。

## 1. 环境

| 项 | 值 |
|---|---|
| OpenWrt | 24.10.8，`armsr/armv8` rootfs，aarch64 |
| Ruby / Psych | `ruby 3.3.10` / `Psych 5.1.2`（`opkg install ruby ruby-psych`） |
| OpenClash 控制器 | mihomo `v1.19.33`，`/usr/bin/clash`，external-controller `127.0.0.1:19090`，secret `cfip-openclash` |
| 配置 | `/etc/openclash/config/config.yaml`，真实备份 `config.yaml.bak.<id>` |
| LuCI | uhttpd + rpcd，当前分支源码经 `tests/real-luci-ui-provision.sh` 注入 |
| 验证方式 | 真实文件、真实 rpcd RPC、Playwright 真实浏览器；无 mock DOM |

## 2. 真实恢复（后端链路）

`aarch64-ruby.txt`、`direct-restore.txt`。

| 步骤 | 证据 |
|---|---|
| 恢复前配置 | `47f7286f…`（D） |
| 恢复源备份 | `config.yaml.bak.20261104105022.pre-restore.pKElMj` = `fe6bbace…`（C） |
| RPC 结果 | `success=true`，`nodeFileWritten=true`，`serviceApplied=true`，`deferredUntilServiceStart=false` |
| 恢复后配置 | `fe6bbace…`，与备份字节一致 |
| 服务 | clash PID 47284 → 50976；`PROXY` 组从 `ui-final-node` 变为 `ui-restored-node` |
| 恢复前保护 | 自动生成 `config.yaml.bak.20261104110251.pre-restore` |

同一路径另有一次 A→B 恢复：`config 3b4ed192…` → 备份 `2b2373c5…`，`/group` 返回 `restored-node`，PID 2186→2498。

## 3. UI 恢复

`openclash-ruby-restore.json`、`restore-before.png`、`restore-success-notice.png`、`restore-after.png`。

- 点击 Config Backups 中的 Restore → 确认 modal → 通知 `Backup restored successfully.`。
- 恢复前配置 `fe6bbace…`（C），恢复源 `47f7286f…`（D）；恢复后配置 `47f7286f…`，`PROXY=ui-final-node`（`clashPid=44561`）。
- 截图显示 OpenClash 页面、备份表与成功通知。

## 4. Ruby/Psych 三态 UI 与 RPC

`ruby-states.json`、`ruby-missing.png`、`psych-missing.png`、`ruby-unusable.png`、`ruby-available.png`。

| 状态 | `ruby_status` | UI 文案（人类可读） | Restore |
|---|---|---|---|
| Ruby 缺失 | `ruby_missing` | `Ruby is not installed.` + `Next step: opkg install ruby ruby-psych` | disabled |
| Psych 缺失 | `psych_missing` | `Psych YAML module is missing` + `Next step: opkg install ruby-psych` | disabled |
| Ruby 不能运行 | `ruby_unusable` | `exits with a segmentation fault` + `Next step: Use firmware with a working Ruby/Psych…` | disabled |
| 可用 | `available` | 无警告 | enabled |

三种失败态页面均仍显示 `OpenClash is installed…`，未误报“OpenClash 未安装”；备份列表与删除保持可用，仅 Restore 禁用。`cf-ip-auto --check-env` 与 `--refresh-env` 均返回
`ruby_installed/ruby_usable/ruby_psych/ruby_status/ruby_version/openclash_restore_available` 字段。

## 5. x86_64 Rosetta 边界

`x86-ruby.txt`：

- 容器 `uname -m=x86_64`，`/proc/cpuinfo vendor_id=VirtualApple`（Rosetta 仿真）。
- `ldd /usr/lib/ruby/ruby3.3-bin` 全部解析：musl、libruby、libz、libgmp、libgcc_s；`libyaml` 与 `psych.so` 均存在。
- `ruby -v`、`ruby --disable-gems -v`、`ruby -rpsych` 全部 rc 139，且在输出任何 Ruby 版本前崩溃。
- 同一 OpenWrt 24.10.8 的 `aarch64` 原生容器同版本 Ruby/Psych 正常（`aarch64-ruby.txt`）。

判定：缺库、ABI、Psych/nokogiri 扩展均已排除；根因是 x86_64 在 Apple Silicon Rosetta 下的运行时兼容性。该环境类不支持；用户应使用 aarch64 目标或真实 x86_64 设备。插件在 Ruby 崩溃时给出上面的可读提示，不再把恢复失败归因于 OpenClash。

## 6. 门禁

- `node --check` 全部打包 JS：PASS。
- `tests/i18n-contract.py`：483 keys（JS 474 + menu 9），POT/zh_Hans/en 各 494 条，PASS。
- `tests/openclash-ruby-precheck.sh`：4/4 PASS（missing/psych/unusable/available）。
- `tests/openclash-ruby-precheck.cjs`：5/5 PASS。
- 本地 LuCI fixture 7/7 PASS；`openclash-rpc-contract.sh` PASS；`actionlint` PASS；`bash -n`/`sh -n` PASS。
- 本目录验证未创建 PR、未触发任何 Actions。
