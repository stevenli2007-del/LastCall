# 技术栈与架构约定

## 1. 目标

交付可安装的 iOS / Android 手机 App。HTML 原型只用于表达交互，不作为生产客户端或后端。

## 2. 推荐技术栈

| 层 | 推荐 | 用途与约束 |
|---|---|---|
| 移动端 | React Native + Expo（TypeScript） | 一套代码构建 iOS / Android；使用 Expo managed/CNG 工作流，确需原生改动时再引入 config plugin。 |
| 导航 | Expo Router | 文件路由、原生 stack/tab 和深链接。路由页面只负责 UI 编排。 |
| 相机/条码 | `expo-camera` | 使用 `CameraView` 条码事件；权限在用户进入扫描时请求；相机不可用时提供手动输入。 |
| 客户端缓存 | `expo-sqlite` | 本地缓存与后续离线队列的持久化基础。MVP 写入在线提交；不可把本地缓存当作服务端事实。 |
| 云端 | Supabase | PostgreSQL、Auth、Data API、RLS、数据库函数；Edge Functions 仅用于需要服务端密钥或外部 API 的功能。 |
| 数据访问 | `@supabase/supabase-js` | 客户端仅持有 publishable key；所有暴露表启用 RLS。数据库事务逻辑通过 SQL function/RPC。 |
| 状态/表单 | React hooks + 小型共享 service 层 | 先避免过早引入大型状态框架；若跨屏状态复杂再做 ADR 评估。 |
| 构建发布 | EAS Build / TestFlight / Google Play 内测 | 开发、预发布、生产环境隔离；环境变量按环境配置。 |
| 源码协作 | GitHub | 私有仓库、Issues、Projects、CI、PR 和版本化文档；按单人开发使用，不依赖 CODEOWNERS 或多人审批。 |

官方资料：Expo Router 的多平台路由、Expo Camera 条码扫描、Expo SQLite 和 Expo + Supabase 接入见 [Expo Router](https://docs.expo.dev/router/introduction/)、[Expo Camera](https://docs.expo.dev/versions/latest/sdk/camera/)、[Expo SQLite](https://docs.expo.dev/versions/latest/sdk/sqlite/)、[Expo 使用 Supabase](https://docs.expo.dev/guides/using-supabase/)；Supabase Expo quickstart 说明客户端初始化与 RLS 接入，见 [Supabase Expo React Native](https://supabase.com/docs/guides/getting-started/quickstarts/expo-react-native)、[Supabase RLS](https://supabase.com/docs/guides/database/postgres/row-level-security)。

## 3. 分层

```text
Screens (Expo Router)
  ↓
Feature UI (home / containers / add / remove / settings)
  ↓
Domain services (expiry, cell labels, add/remove use cases)
  ↓
Repositories (Supabase online + SQLite cache)
  ↓
Postgres tables / views / RPC + RLS
```

- 日期规则、格子编号、位置紧凑重排只定义一处；客户端用于预览，数据库是持久化写入与权限的最终裁决者。
- Add 和 Remove 只调用共享 inventory service/RPC，不自行拼 SQL 或复制状态规则。
- 库存新增、条码核验并下架、格内重排都必须由数据库事务完成。
- 首页临期状态实时从门店时区、当前日期、统一临期天数派生。推送通知若需要，后续再增加定时服务。

## 4. 网络与离线

- MVP 要求联网完成库存写入；短时网络失败时保留表单草稿并允许重试，客户端生成幂等操作 ID，避免重复创建。
- 可缓存首页和容器数据，明确标注“最后同步时间”；不要在离线状态误报写入成功。
- Phase 5 再决定完整离线写入。实施前需确定冲突规则、删除/重排的顺序、重试幂等和多设备合并策略。

## 5. 安全和配置

- Supabase publishable key 可在客户端，service-role/secret key 绝不能进入 App、提交记录或客户端 `.env`。
- 所有门店业务表按 `store_id` 隔离；RLS 从用户的 `store_members` 关系判定授权。
- SQL schema 通过 `supabase/migrations` 版本化；开发环境使用本地 Supabase。远端 Dashboard 手动变更需立即写成 migration。
- `.env.example` 只放变量名和假值；实际密钥放在未跟踪的本地 env/CI secret。
- 依赖版本锁定在 lockfile；Expo SDK 升级和关键依赖升级单独建 Issue/PR。

## 6. 选型依据和限制

Expo 官方文档提供 iOS/Android 共用的路由与相机能力；Supabase 提供托管 Postgres、Auth 和 RLS。这个组合适合小团队先验证门店工作流并保留 SQL 可迁移性。它不自动解决离线多端冲突、条码扫描质量、相机权限 UX 或 OCR；这些分别由试点和后续 Phase 验证。
