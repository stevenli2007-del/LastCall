# 决策记录（ADR）

本文记录当前已确认的关键决策。新增决定按日期倒序追加，不删除旧记录；被替代时标记 superseded 并链接新决定。

## ADR-008 · MVP 开发先聚焦 iOS

- **状态：** Accepted（owner 2026-10-23）
- **背景：** 项目进入 T0.3 工程初始化阶段；owner 决定当前开发只推进 iOS App。
- **决定：** T0.3 起的当前开发与验收范围限定为 iOS。Android 工程构建、设备验证和发布工作暂缓，直到 owner 另行决定恢复。
- **影响：** Expo 工程明确配置仅支持 iOS，Roadmap 的当前开发验收按 iOS 执行。该决定调整实施顺序，不替代 ADR-001 中长期产品仍面向 iOS / Android 的目标。

## ADR-001 · 正式产品为 iOS / Android App

- **状态：** Accepted
- **背景：** 当前 HTML 只用于表达交互；店员的主要场景发生在手机上并需要相机。
- **决定：** 生产客户端使用跨平台原生 App；HTML 原型不作为生产实现。
- **影响：** 采用 Expo + React Native + TypeScript；必须验证真实设备相机、权限与发布流程。

## ADR-002 · 容器按正视图格子与纵深容量建模

- **状态：** Accepted
- **背景：** 3×2×5 的旧显示把纵深容量误画成更多格位。
- **决定：** 3×2 是六格 A–F；5 是每格纵深容量。单件位置为 A1–A5 等。
- **影响：** DB 分开保存 cell 和 depth index；移除后同格紧凑重排。

## ADR-003 · 每件实物独立追踪日期和条码

- **状态：** Accepted
- **背景：** 同 SKU 可有不同生产日期和位置，同条码可能多件同时在库。
- **决定：** 一件实物一条 inventory row；barcode 不是唯一键。
- **影响：** Remove 必须先选中具体单件再扫码精确核验。

## ADR-004 · 过期日按生产日加预计存储天数计算

- **状态：** Accepted
- **背景：** 示例定义生产日期 2026-01-01、预计 10 天应于 2026-01-11 过期。
- **决定：** 生产日期当天计作第 0 天，使用日历日加法；临期天数由门店统一设置。
- **影响：** 1 天阈值时 1 月 10 日临期，1 月 11 日起过期；按门店时区派生状态。

## ADR-005 · MVP 使用 Expo 与 Supabase

- **状态：** Accepted（owner 2026-10-23）
- **背景：** 小团队需共享 iOS/Android 客户端、认证、Postgres 与权限控制。
- **决定：** 推荐 Expo React Native + TypeScript、Supabase Auth/Postgres/RLS，SQLite 用于本地缓存基础。
- **影响：** 需要真实设备试点；MVP 不承诺离线写入。若确定必须完全离线，重新评估同步方案。

## ADR-007 · 单人开发直推 `main`，不启用分支保护

- **状态：** Accepted（2026-10-23，owner 决定）
- **背景：** 本项目为单人开发，feature branch + PR 流程带来额外开销；私有仓库使用 GitHub Free 计划，branch protection API 返回 403（"Upgrade to GitHub Pro or make this repository public"），无法启用强制保护。
- **决定：** ① `main` 是唯一长期分支，日常改动直接提交到 `main`；② feature branch/PR 降为可选留档手段，不再是任务完成的前置条件；③ 不启用分支保护，改用提交前自查（`git status`、类型/构建检查）与「`main` 始终可构建」保证；④ GitHub Issue 仍是任务范围与验收标准的记录来源；重要节点建议打 tag 便于回滚。
- **影响：** 回滚依赖 commit 历史与 tag，不再有分支级隔离。同步更新 `AGENTS.md`、`docs/DEVELOPMENT_CONSTITUTION.md` §3/§4、`docs/ROADMAP.md`。若将来转为多人协作或升级 GitHub 计划，需重新评估并 supersede 本决定。

## ADR-006 · 门店默认临期阈值为 2 天

- **状态：** Accepted
- **背景：** MVP 需要为新门店定义统一的临期提醒起始阈值，同时允许门店根据实际管理需要调整。
- **决定：** 新门店的 `near_expiry_days` 默认值为 2 天；管理员可调整。状态仍按门店本地日期动态计算，过期当天及之后为过期。
- **影响：** PRD、数据库设计和交互原型均以 2 天作为默认值；阈值范围与权限按对应文档执行。
