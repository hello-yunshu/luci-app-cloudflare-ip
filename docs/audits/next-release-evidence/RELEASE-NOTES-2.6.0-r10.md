## Cloudflare IP `2.6.0-r10` — Pre-release（非 stable）

发布对象：`luci-app-cloudflare-ip` `2.6.0-r10`，tag `v2.6.0-10` → `cbc17a7e629ed0e7c96e62874f2976a5e2b6ac4a`。
通道：`release-channel.json` 仍为 `stable`；自动晋级被 `release.yml` guard 禁用，本版本按仓库惯例手动发布为 **Pre-release**，`make_latest=false`。

### 下载

- OpenWrt 24.10.x：`luci-app-cloudflare-ip_2.6.0-r10_all.ipk`
- OpenWrt 25.12+：`luci-app-cloudflare-ip-2.6.0-r10.apk`

只安装主包即可使用 Native、Adaptive Measurement 与 Operational Health。Rill integration 已包含在主包；`rill-runtime-preview` 可选，不在本 Release 中。

### 产物与校验

```
f56e55267f311a5b47bc11a73c07c2d92de058921ee7211fb03af706742b9a98  luci-app-cloudflare-ip_2.6.0-r10_all.ipk
4ba2dad6d4cd0689b22cbb263bca1b6359ed754b6fa98c20cd29b7e9a5c19ae8  luci-app-cloudflare-ip-2.6.0-r10.apk
```

`qualification.json` 绑定 exact-SHA CI：run `42481820841` / attempt `1` / commit `cbc17a7`。本地已通过 `validate-release-assets.py` 与 `tests/release-asset-contract.sh`。

### 本版变化

**运行期**
- `measurement_timeout` 默认 60 → 180 秒（仅新装或该值未设置时写入；已设置值保留；clamp 20–300）。
- 启动竞态修复：首次运行只保留一个后台作业，避免两个作业争抢 `attempts=1` 写锁导致首轮静默丢失。
- `sysupgrade` keep-list 改为临时文件 + rename 原子写：断电只会留下旧文件或完整的新文件。
- 升级保留 OpenClash 外部自定义配置：已存在目标仅接受 root 拥有、私有、无符号链接的文件；不在 `/etc/openclash` 之外新建。
- legacy `cron_custom` 表达式保留，不再被静默替换为 6h 默认。
- publisher 就绪检查在 curl 8.22.0 下不再恒定失败（r9 已修复，r10 延续）。

**UI**
- P0/P1 修复与 P2 一致性收尾：对比度、banner 边框、状态文案、设置页分组、Intelligence 折叠/表格、按钮与输入框回归主题原生皮肤、空态文本化等。

**文档/证据**
- 12h soak 等价验收记录、UI 设计规范与视觉证据、发布证据索引。

### r9 → r10 升级路径（重点）

1. 覆盖安装：IPK `opkg install --force-depends <包>`；APK `apk add --allow-untrusted <包>`。
2. `/etc/config/cf_ip` 是 conffile：升级保留用户已有值；`measurement_timeout` 只在缺失时写入 `180`。
3. OpenClash 外部配置路径与自定义 cron 表达式保留；`/etc/sysupgrade.conf` 的 CFST 路径经原子重写后保持。
4. 升级后重启服务：`/etc/init.d/cf_ip restart`；确认 `ubus call cf_ip status` 返回 `running=true`。
5. 历史 SHA 校验：r8/r9 资产与 GitHub API `digest` 一致；本地链式 8→9→10 复现两格式通过（见 `docs/audits/next-release-evidence/local-reproduction-20261108.md`，标注 `LOCAL_REPRODUCTION`，**不替代 CI 门禁**）。

### 验收依据与边界

- exact-SHA CI `42481820841`（`cbc17a7`）全绿：package identity、IPK/APK build、Real package drill、Real package migration、rootfs-contract、real-cfst-smoke、workflow-lint、evidence-manifest、qualification-guard 等。
- 12h soak 为 **用户裁定的等价验收**（measured `4659503`/r9，`ROOT_TREE_IDENTICAL` 至 `30d6c31`），**不是 exact-artifact 12h pass**；`30d6c31` 窗口按用户指令提前终止，未写 `SOAK_DONE`。
- GitHub `releases/download` 曾多次返回 504/503/连接中断（`api.github.com` 正常、状态页无事件）；证据与时间线见 `docs/audits/next-release-evidence/incident-20261108-github-asset-delivery.md`。
- 本地 8→9→10 复现仅用于避免链路停摆；恢复后 CI drill 已重跑并作为正式门禁。

### 已知未修（不挡发布，本轮未改动）

- P2-01 600/900 媒体查询、P2-02 Overview 内联 CSS、P2-03 深色变量双来源（OPEN — SOURCE_CONFIRMED）。
- P2-11 深色 danger 徽标对比度约 3.6:1（OPEN — ACCEPTED，待主题侧提亮 `--danger-color`）。
- P3-01 中文术语表、P3-02 设计 token/footer 一致性（OPEN）。
- 非发布资产的 zstd 依赖 advisories（仅 workspace `polars`，未进入任何发布产物）待用户决定。

### BLOCKED / 未跑（边界不变）

- PassWall 真实代理网络（设备未安装）。
- 真实断电 drill（无 hypervisor 控制，且会打断 soak）。
- 物理触摸、软键盘、多指手势（仅有浏览器仿真）。
- OpenClash 完整 backup/restore/delete 真实矩阵（已有容器与部分设备证据，完整矩阵未跑）。
- aarch64 实机（仅有仿真容器证据）。

安装前请备份 `/etc/config/cf_ip` 与 OpenClash 配置；本版本为 Pre-release，不建议直接替换 stable 通道。
