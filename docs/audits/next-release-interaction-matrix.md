# Next Release Interaction Matrix — 2e28db4

基线：`main` / `2e28db4b5cdc221897bbe98ff78fbe7235098e53`。

## 1. 状态定义

- **PASS**：在真实 LuCI/Aurora 运行环境实际执行，结果符合预期。
- **FAIL**：实际执行或用真实 JS 模块 harness 复现，结果不符合预期。
- **BLOCKED**：环境/工具无法完成该交互（例如 native `confirm()` 被自动化自动 dismiss，或真实控制器不可用）。
- **NOT-RUN**：本轮未实际执行，仅有源码/库存或视觉正常态证据；不得算完成。

## 2. 8 页面 × 7 状态

| 页面 | 1 正常/首次加载 | 2 加载中/重复点击/禁用 | 3 空数据/首次安装/依赖缺失 | 4 RPC 超时/网络/权限/异常响应 | 5 校验/未保存/保存/应用/回读/重启 | 6 成功/失败/部分完成/回退/取消/刷新 | 7 弹窗/下拉/表格/键盘/触控 |
|---|---|---|---|---|---|---|---|
| Overview | **PASS** `V-OV` | NOT-RUN | **PASS** `V-OV`（CFST 未安装） | NOT-RUN | NOT-RUN（只读视图，无 Save；动作未完成） | NOT-RUN `I-OV-REFRESH` | NOT-RUN |
| Settings | **PASS** `V-SET` | NOT-RUN | **PASS** `V-SET`（无依赖状态） | NOT-RUN | NOT-RUN `I-SET-VALID`（invalid/valid 保存未得到可判定结果） | NOT-RUN | NOT-RUN |
| Sources | **PASS** `V-SRC` | NOT-RUN | **PASS** `V-SRC`（无自定义来源） | **FAIL** `J-RPC-SRC` | **FAIL** `J-SRC-RELOAD` | **FAIL** `J-SRC-RELOAD`（刷新 reload；真实刷新受容器网络限制） | NOT-RUN（MultiValue 可见，键盘未测） |
| Intelligence | **PASS** `V-INT` | NOT-RUN | **PASS** `V-INT`（Rill 未安装/禁用） | NOT-RUN | NOT-RUN | **FAIL** `J-RILL-RESET` | **BLOCKED** `I-RILL-RESET`（native confirm） |
| OpenClash | **PASS** `V-OC` | NOT-RUN | **PASS** `V-OC`（无备份；controller stub） | **FAIL** `J-RPC-OC` | NOT-RUN（无真实 OpenClash 控制器） | **FAIL** `J-DELETE`（删除假成功） | **FAIL** `J-DELETE`（modal 打开，结果假成功） |
| PassWall | **PASS** `V-PW` | NOT-RUN | NOT-RUN（stub 已安装；未安装态未截图） | NOT-RUN | NOT-RUN | NOT-RUN | NOT-RUN |
| Advanced | **PASS** `V-ADV` | NOT-RUN | NOT-RUN | NOT-RUN | NOT-RUN | NOT-RUN | NOT-RUN |
| Logs & Records | **PASS** `V-LOG` | NOT-RUN（曾观察到“加载视图中”，复测已加载，未做受控加载态） | **PASS** `V-LOG`（空日志） | NOT-RUN | NOT-RUN（只读视图） | NOT-RUN（Clear 未执行） | **BLOCKED**（native confirm） |

**统计：56 格 = 21 PASS / 7 FAIL / 2 BLOCKED / 26 NOT-RUN。**

## 3. 证据索引

| 证据 ID | 内容 | 路径/命令 |
|---|---|---|
| `V-OV` | Overview 8 页 × 3 主题 × 3 断点正常态 | `visual-2e28db4/*/*/overview.png` |
| `V-SET` | Settings 截图 | `visual-2e28db4/*/*/settings.png` |
| `V-SRC` | Sources 截图（含 320/200% 边界） | `visual-2e28db4/*/*/sources.png` |
| `V-INT` | Intelligence 截图 | `visual-2e28db4/*/*/intelligence.png` |
| `V-OC` | OpenClash 截图（无备份空态） | `visual-2e28db4/*/*/openclash.png` |
| `V-PW` | PassWall 截图 | `visual-2e28db4/*/*/passwall.png` |
| `V-ADV` | Advanced 截图 | `visual-2e28db4/*/*/advanced.png` |
| `V-LOG` | Logs 截图（空日志） | `visual-2e28db4/*/*/logs.png` |
| `J-DELETE` | OpenClash `{success:false}` 无 error → “Backup deleted” | `repro-2e28db4/repro-output.json` |
| `J-RPC-OC` | OpenClash RPC reject → “OpenClash Not Found” | 同上 |
| `J-RPC-SRC` | Sources registry/status reject → 空表、无错误 | 同上 |
| `J-SRC-RELOAD` | Sources 刷新 reload=1、save=0、未保存草稿 | 同上 |
| `J-RILL-RESET` | Rill reset 成功后 generation 不变、reload=0 | 同上 |
| `I-OV-REFRESH` | 真实 Overview 刷新环境点击，无可见 toast 捕获 | `interactions-2e28db4/2e28db4-aurora-light-1280x900-overview-refresh.png` |
| `I-SET-VALID` | Settings `ip_count=0` 保存尝试；UCI 仍为 4，未捕获 validation bubble | `interactions-2e28db4/2e28db4-aurora-light-1280x900-settings-invalid.png` |
| `I-RILL-RESET` | Intelligence 重置点击；native confirm 被自动 dismiss | `interactions-2e28db4/2e28db4-aurora-light-1280x900-intelligence-reset.png` |

## 4. 复现命令

```sh
cd /Users/yunshu/Documents/GitHub/luci-app-cloudflare-ip
node docs/audits/next-release-evidence/repro-2e28db4/repro-risks.cjs \
  > docs/audits/next-release-evidence/repro-2e28db4/repro-output.json
```

关键结果：

- `openclash_delete.false_success = true`
- `rpc_failure_openclash.not_installed = true`
- `rpc_failure_sources.rows = 0`、`error_visible = false`
- `sources_refresh.reload_calls = 1`、`save_calls = 0`
- `rill_reset.reload_calls = 0`、`status_generation_after = 1`、`stale_status = true`

## 5. 未覆盖/阻塞说明

- **真实 OpenClash/PassWall 控制器**：页面用可执行 init stub 暴露；真实代理服务/配置事务未在本轮运行。OpenClash 备份列表为空，未做真实恢复/删除成功路径。
- **RPC 异常注入**：OpenClash/Sources 用 JS harness；真实 ubus 权限/超时注入未做。
- **native confirm**：agent-browser 默认自动 dismiss，Diagnostics/Rill 的确认/取消未实际判定；标记 BLOCKED。
- **表单保存/应用**：Settings 的 invalid/valid 保存没有改变 UCI，且未捕获 validation bubble；不能算 PASS，也未判定为产品失败。
- **键盘/触控**：未做 Tab/Esc/Enter/触摸命中测试；全部标 NOT-RUN。
- **真实设备**：全部控制器/硬件/网络/soak 仅容器级；物理设备 NOT-RUN。

## 6. 结论

- 正常态与空态覆盖完整（8/8 页面，真实 LuCI/Aurora）。
- 4 个高风险交互均已复现：删除假成功、RPC 错误折叠、Sources 刷新丢失草稿、Rill reset 旧状态。
- 表单保存、真实控制器、键盘/触控仍大量 NOT-RUN/BLOCKED，不能据此写“交互全通过”，也不能进入阶段 B。
