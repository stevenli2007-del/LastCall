# 临期宝 LastCall

临期宝是面向便利店店员的库存位置与保质期管理 App。当前仓库包含交互式 HTML 原型；正式产品目标是 iOS / Android 手机 App。

## 项目文档

- [产品需求 PRD](docs/PRD.md)
- [开发路线图 Roadmap](docs/ROADMAP.md)
- [技术栈 Tech Stack](docs/TECHSTACK.md)
- [数据库设计 Database](docs/DATABASE.md)
- [开发宪法与协作约定](docs/DEVELOPMENT_CONSTITUTION.md)
- [决策记录 ADR](docs/DECISION_LOG.md)
- [仓库级 AI 开发约定](AGENTS.md)

## 当前状态

- 产品流程与主要交互已通过 `index.html` 原型演示。
- 原型中的摄像头、条码和日期识别均为模拟交互。
- GitHub 私有仓库 `stevenli2007-del/LastCall` 已创建，文档与原型基线已推送到 `main`；正式 App 代码和云端项目尚待初始化。
- 项目采用单人开发流程：项目 owner 负责决策、排序和验收；改动直接提交到 `main`，Issue 记录任务范围与验收标准（ADR-007）；Codex 按当前任务协助。

## 重要产品定义

容器的行数 × 列数表示正视图格子数；每格容量表示纵深可放的商品数。例如 3 × 2 × 5 表示正视图 6 格 A–F，每格可存放 5 件，位置为 A1–A5、B1–B5，以此类推。生产日期加预计存储天数得到过期日期；状态按门店时区和统一临期天数计算。
