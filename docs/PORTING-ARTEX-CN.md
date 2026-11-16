# ARTEX-Pro 移植说明（ARTEX-CN → ARTEX-EN 基线）

本仓库 **ARTEX-Pro** 以 `ARTEX-EN`（原 `ARTEX--2`，fork 自 [BaaRai/ARTEX](https://github.com/BaaRai/ARTEX)，英文工程基线，826 文件 / 284 个 Go 测试 / 0.6.0 + 最新 main）为底座，
把 `ARTEX-CN`（原 `ARTEX2`，fork 自 [RuoJi6/ARTEX](https://github.com/RuoJi6/ARTEX)，v0.3.18 中文版）在 0.3.16–0.3.18 里新增的**业务模块**移植过来。

两个仓库都在 2026-10-07 的 v0.3.15 之后分叉，因此这次移植是"把 CN 的业务功能接到 EN 的新架构上"，不是简单合并。

## 一、移植内容

| 模块 | 来源（ARTEX-CN） | 说明 |
| --- | --- | --- |
| 日历式计划任务 | `db/schedules.go`、`server/schedules.go`、`server/calendar_schedule.go`、`web/src/app/(main)/function/schedules/page.tsx` | 按周/单次的时间窗口自动暂停、恢复任务；手动暂停优先级高于计划 |
| 漏洞归并（finding cases） | `db/finding_cases.go`、`db/finding_case_reviews.go`、`agent/finding_cases.go`、`server/finding_cases*.go`、`web/src/components/finding-case-list.tsx`、`web/src/app/(main)/function/findings/case/page.tsx` | 同一实际缺陷的多次上报归并成"统一报告"，保留原始报告与证据；支持人工整理与旁路问答 |
| HTTP Basic Auth 访问控制 | `server/basic_auth.go`、`web/src/app/(main)/system/settings/_components/basic-auth-card.tsx` | 可选开关，整站前置网关（Cookie 会话 + Basic 头） |
| 审批脚本审查 | `intercept/scripts.go` + 对 `intercept/review_context.go` 的合并 | 审批时把被引用脚本的完整快照（路径/SHA-256/大小/源码）交给审查模型；快照不完整时强制转人工 |
| 前端组件 | `web/src/components/date-select.tsx`、`time-select.tsx` | 计划任务的日期/时间选择器 |

## 二、为接上 EN 架构所做的集成改动

Go 侧（编译与 vet 通过）：

- `intercept/review_context.go`：新增 `ReviewScript` 类型、`ScriptCaptureStatus`/`Scripts` 字段，`BuildReviewInput` 调用 `captureScripts`；新增 `guardIncompleteScripts`，在 `closed_judge.go` 与 `intercept.go`（freeform 路径）里把"快照不完整 + 允许"升级为转人工。
  > 说明：CN 用 `IncompleteScriptAction` 配置项控制这条策略，这里固定为"转人工"（更保守），没有加配置项。
  > 另外：只有真正引用了脚本的调用才会带上 `script_capture_status` 字段，普通调用的审查输入与上游完全一致（避免影响既有 golden 测试）。
- `agent/assembly.go` + `agent/deferred.go`：新增 `DeferredInfo.CaseGuidance`，reporter 绑定归并工具时才注入归并/历史整理提示词；历史整理模式下裁剪可用工具集。
- `agent/cancelcause.go`：新增 `AbortPausedBySchedule` 取消原因。
- `server/manager.go`：`ApplyTaskPauseOrigin`（记录 `schedule_paused` 来源，保留 EN 的 `paused_at`）。
- `server/task_control.go`：暂停走来源感知路径；恢复沿用 EN 的 `admitTaskWhen`。
- `server/scheduler.go` / `server.go`：`Scheduler.startedAt`、每 tick 调用 `fireTaskSchedules`（即使没有 P3 触发器也执行）、`Server.scheduleMu`。
- `server/conversations.go`：`triggeredRun.conversationID`，人工整理的预建会话不会被合并，运行/失败状态回写 `finding_case_review_runs`。
- `server/orchestration.go`：`orchestrationTools()` 追加 `findingCaseTools()`，初始化时 `seedFindingCaseTools()`。
- `server/dto.go` / `db/findings.go`：`FindingDTO.CaseID/MemberIDs`、`DBFinding.ExportCaseID/ExportMemberIDs`（统一报告导出用 `case:<id>` 标识）。
- `db/settings.go`：新增 `SetSettingContext`（Basic Auth 网关的写超时）。
- `db/tasks.go` + `server/server.go`：任务创建可携带 `schedule`，在同一事务里建计划、绑定任务并把任务置为 `schedule_paused` 停放（与 CN 一致）。
- `server/server.go` + `auth.go`：注册 `/api/schedules*`、`/api/exploration/finding-case*`、`/api/settings/basic-auth`、`/api/basic-auth/check`；`requireBasicAuth` 包在整个 mux 外层，check 端点豁免 JWT。
- 数据库：`db/schema.sql` 追加新表；`db/migrations/0005_schedules_finding_cases.sql` 供已有库升级（幂等，含 `finding_case_changed()` 触发器与 `tasks.schedule_paused` 列）。

## 三、没有移植的

- **`selfupdate` 在线自更新**（`selfupdate/*`、`server/update.go`、`web/.../update-card.tsx`、`update-badge.tsx`）：按要求排除。EN 自带的 `ARTEX_UPDATE_CHECK` 更新横幅未改动。
  > 提醒：CN 的自更新源写死 `RuoJi6/ARTEX`，在这种二开仓库里点更新会覆盖本地改动，本来也不建议启用。
- CN 的 `screenshots/dashboard.png`、`wx.png`、`docs/漏洞流量证据.md`（EN 已有对应的 `docs/vulnerability-traffic-evidence.md`，内容相同，不重复放）。

## 四、已知差异 / 降级

1. **界面语言**：EN 基线是英文界面；移植过来的 4 个模块页面与提示词**保留中文**（与 CN 一致）。导航项用英文 `Schedules`。如需统一，可再做一轮翻译。
2. **归并列表入口**：EN 的 findings 列表页被上游重写过，没有把 CN 的"组内折叠"整套搬进来；改为独立的 `/function/findings/cases` 列表页 + findings 页顶部入口，case 详情页功能完整（统一报告 / 原始上报 / 归并历史 / 重新生成 / 移出成员）。
3. **CN 的 `AdmitWhenScheduled` 准入改造**：没有整体替换 EN 的任务准入（EN 有 intent claim lease 等新机制），计划窗口的"人工暂停优先"改为在 `calendar_schedule.go` 里读 `schedule_paused` 判断。
4. **数据库测试未运行**：本机没有 PostgreSQL/Docker，`db`、`server` 里依赖数据库的测试没有执行；只有 `go build ./...`、`go vet ./...`（含测试编译）和 `intercept`/`agent` 的纯单元测试通过。上线前建议在 CI 或本地 `docker compose up` 跑一遍 `go test ./...`。

## 五、验证记录

- `go build ./...` ✅
- `go vet ./...` ✅（含全部 `_test.go` 编译）
- `go test ./intercept -run 'Review|Script|Closed'` ✅
- `go test ./agent -run 'Finding|Deferred'` ✅
- `go build -o build/artex.exe ./cmd/artex` ✅（44.5 MB）
- `pnpm build`（web/）✅：新增路由 `/function/schedules`、`/function/findings/case`、`/function/findings/cases` 均静态产出
- `go test ./...` 未跑：db/server 的测试需要 PostgreSQL（本机无 Docker），上线前请在 CI 或 `docker compose up` 环境执行
