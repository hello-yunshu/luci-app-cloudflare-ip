# Next Release Evidence — 2e28db4

基线：`2e28db4b5cdc221897bbe98ff78fbe7235098e53`（`main`）。

## 内容

| 路径 | 内容 |
|---|---|
| `baseline-2e28db4.json` | 仓库/HEAD/worktree/tag/Release/CI 基线 |
| `environment-2e28db4.json` | 真实 LuCI/Aurora 容器、主题、浏览器、fixture |
| `cross-repo-2e28db4.json` | rill-openwrt-packages / rill-ml / performance-manager HEAD 与 open PR |
| `visual-2e28db4/` | 78 张真实 LuCI 截图、`metrics.jsonl`、`visual-index.csv`、`capture-visual.sh` |
| `interactions-2e28db4/` | 真实浏览器交互截图与 `observations.json` |
| `repro-2e28db4/` | 4 项风险的可执行 harness、输出 JSON |
| `i18n-2e28db4/` | 423/88 逐文件数据、缺失 key TSV |

## 视觉截图计数

- 正常态：3 主题 × 3 断点 × 8 页面 = 72
- 边界：320×900 Overview × 3 主题 = 3；1280@200% 等效 640×900 Sources × 3 主题 = 3
- 合计：**78 PNG**
- 所有正常态/边界截图 `overflow=false`；Aurora dark 26/26 `data-darkmode=true`；无登录页。
- 320 Overview 存在顶部导航 tab 裁切（P2-07）。

## 风险复现

```sh
cd /Users/yunshu/Documents/GitHub/luci-app-cloudflare-ip
node docs/audits/next-release-evidence/repro-2e28db4/repro-risks.cjs \
  > docs/audits/next-release-evidence/repro-2e28db4/repro-output.json
```

结果：`openclash_delete.false_success=true`、`rpc_failure_openclash.not_installed=true`、`rpc_failure_sources.rows=0/error_visible=false`、`sources_refresh.reload_calls=1/save_calls=0`、`rill_reset.reload_calls=0/stale_status=true`。

## 边界

- 真实物理设备、硬件矩阵、24h soak：**NOT RUN**。
- 真实 OpenClash/PassWall 控制器、真实代理网络：**NOT RUN**；页面使用 init stub 暴露路由。
- WCAG AA 全量对比度、全量 console、键盘/触控：**NOT RUN**。
- 200% 缩放为 640 CSS px 有效宽度近似，不是精确浏览器 zoom。
- 审计容器与 fixture 不属于产品代码；审计完成后清理容器/镜像，保留本目录证据。
