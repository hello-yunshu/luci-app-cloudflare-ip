# Changelog

本文件只记录已闭合、可由 exact-SHA CI 复现的用户可见变更。历史版本详情以对应 GitHub Release 的 `qualification.json` 与 Release notes 为准。

## v2.6.0-8 — 2026-11-04

### 修复

- OpenClash 备份删除只在 `success === true` 时提示成功；失败时保留错误与备份文件，不再假成功刷新。
- RPC 失败与“未安装/空数据”分离：OpenClash、Sources、PassWall、Settings 的失败显示人类可读说明 + 可展开/可复制的技术详情。
- Sources 刷新不再整页 reload，保留未保存的自定义来源/预算草稿。
- Rill reset 成功后重新读取并反映状态；修复 LuCI `form.Button` 的 `ev.currentTarget` 事件参数导致的 busy 态缺失。
- 简体中文补齐：516 keys（JS 507 + menu 9），POT/zh_Hans/en 各 552 条；动态状态码与 raw error 进入语言门禁。

### 变更

- legacy 自更新下线：`AUTO_UPDATE=false`、`SELF_UPDATE_URL=""`；`--self-update` 返回失败（rc 1），自动运行路径不再 fetch 或替换脚本。
- Advanced 的弃用字段 `self_update_url` 改为只读；保留 UCI 字段以避免升级丢配置。
- `uhttpd` 从硬依赖移除，仅 LAN Result Publisher 在运行时探测；nginx/lighttpd 系统不会被动安装第二套 Web 服务。
- 统一错误呈现与动态状态映射；深色配色只由 LuCI/Aurora `data-darkmode` 决定。

### 验证

- 51 点七态矩阵：357 个状态单元，121 PASS / 236 N/A / 0 FAIL；覆盖算法 `PASS/(PASS+FAIL)=121/121=100%`。
- 真实 Chrome 125%/150%/200% 页面缩放 + 320 reflow：8 页 × 3 档 0 横向溢出、0 文字截断、0 主内容焦点环缺失；zh_cn 375/1280 共 16 页 0 英文残留、0 msgid 泄漏、0 截断。
- 本地测试盘点：254 个脚本，247 在 CI，7 个登记理由排除，0 遗漏；`tests/ci-test-inventory.py` 在 CI `workflow-lint` job 强制检查。
