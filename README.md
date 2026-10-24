# 临期宝 LastCall

临期宝是面向便利店店员的库存位置与保质期管理 App。当前仓库包含交互式 HTML 原型；正式产品目标是 iOS / Android 手机 App。

## 项目文档

- [产品需求 PRD](docs/PRD.md)
- [开发路线图 Roadmap](docs/ROADMAP.md)
- [技术栈 Tech Stack](docs/TECHSTACK.md)
- [数据库设计 Database](docs/DATABASE.md)
- [设计系统与屏幕清单](docs/DESIGN_SYSTEM.md)
- [开发宪法与协作约定](docs/DEVELOPMENT_CONSTITUTION.md)
- [决策记录 ADR](docs/DECISION_LOG.md)
- [仓库级 AI 开发约定](AGENTS.md)

## 工程结构

```text
apps/mobile/    Expo React Native App（iOS 优先，ADR-008）；设计 token 在 src/constants/tokens.ts
supabase/       migrations（schema 唯一来源）与 seed.sql
scripts/        setup-supabase.sh：本地后端一键初始化（需要 Docker）
docs/           产品与技术文档
index.html      交互原型（仅作参考，非生产代码）
```

后端初始化（需要 Docker Desktop，也可改为手动把 SQL 粘到云端 Supabase 项目）：

```bash
cd apps/mobile && npx expo run:ios -d "iPhone 17"   # 启动 iOS 开发版
npm run db:setup                                    # 初始化本地 Supabase（需 Docker）
```

## 当前状态

- 产品流程与主要交互已通过 `index.html` 原型演示；原型中的摄像头、条码和日期识别均为模拟交互。
- T0.1–T0.5 已完成：术语冻结、仓库初始化、Expo iOS 工程（SDK 58，可在 iOS 模拟器启动）、Supabase 迁移与种子、设计 token 与屏幕清单。
- 后端本地栈尚未启动（Docker 未安装 / 未运行）；迁移文件可直接用于本地或云端 Supabase。
- 当前开发目标为可在真机 iPhone 上演示的 demo，暂不上架 App Store。
- 项目采用单人开发流程：项目 owner 负责决策、排序和验收；改动直接提交到 `main`，Issue 记录任务范围与验收标准（ADR-007）；Codex 按当前任务协助。

## 重要产品定义

容器的行数 × 列数表示正视图格子数；每格容量表示纵深可放的商品数。例如 3 × 2 × 5 表示正视图 6 格 A–F，每格可存放 5 件，位置为 A1–A5、B1–B5，以此类推。生产日期加预计存储天数得到过期日期；状态按门店时区和统一临期天数计算。
