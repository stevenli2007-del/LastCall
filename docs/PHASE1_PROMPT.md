# Phase 1 开工 Prompt

粘贴到新对话框（Codex / Claude）即可开工。内容自包含，不依赖当前会话。

---

你是**临期宝 LastCall** 的实现助手。这是一个给便利店店员用的保质期与货位管理 iOS App。

## 0. 工程位置与环境（硬约束，先读）

- 工程路径：**`/Users/youchengli/Desktop/LastCall`**（路径必须全程纯 ASCII —— 中文路径会让 CocoaPods 在 `hermes-engine.podspec` 上抛 `incompatible character encodings: BINARY and UTF-8`，这是踩过的坑，不要挪回中文路径）
- 远程：`github.com/stevenli2007-del/LastCall`，单人开发，**直接提交 `main`**，不建 feature branch
- 平台：**只做 iOS**（ADR-008）。不要添加或修改任何 Android 配置
- 所有代码实现都在 `apps/mobile/` 下（Expo SDK 58 / RN 0.88 / React 19.3 / expo-router 58）
- **注意**：本工程用的是 `src/app/` 目录路由（不是 `app/`），现有文件为 `src/app/_layout.tsx`、`src/app/index.tsx`、`src/app/explore.tsx`
- Xcode 原生构建（pod install / `expo run:ios`）在沙箱里会被文件删除拦截 → **不要自己跑**，把命令给我，我在本机终端执行

## 1. 必读文档（动手前全部读完）

| 文件 | 看什么 |
|---|---|
| `docs/PRD.md` | 四条核心规则：3×2×5 建模、一物一行（条码不唯一）、过期日 = 生产日 + 保质天数、扫码核对 + 原子重排 |
| `docs/DESIGN_SYSTEM.md` | 设计原则、token 表、**11 个屏幕清单**（路由 / 关键元素 / 必须处理的状态）、10 个复用组件、文案约定 |
| `apps/mobile/src/constants/tokens.ts` | 唯一 token 来源 |
| `docs/DEVELOPMENT_CONSTITUTION.md` | 开发宪法与提交纪律 |
| `docs/DECISION_LOG.md` | ADR，尤其 ADR-008（iOS only） |
| `AGENTS.md` | 仓库级约定 |
| `index.html` | 交互原型（交互参考，不是生产代码） |

## 2. 当前状态：Phase 0 已全部完成

- T0.1 术语冻结 ✅ ｜ T0.2 仓库 ✅ ｜ T0.3 Expo iOS 工程 ✅（模拟器已跑通）｜ T0.4 Supabase schema ✅（文件已交付，本地栈不跑）｜ T0.5 设计 token + 屏幕清单 ✅
- 最新提交 `5edbade`，与 `origin/main` 同步
- **后端尚未接入**：Phase 1 一律用本地假数据（mock），不要接 Supabase、不要装 `@supabase/supabase-js`

## 3. 本次任务：T1.1 建立底部导航

一次只做这一个 Task，做完验收通过再做 T1.2。不要在本次任务里提前实现 Phase 2/3 的业务逻辑。

**范围**

1. 把现有 `src/app/` 改成 tabs 结构，5 个 tab，顺序与文案固定：

   | 路由文件 | 标题 | 说明 |
   |---|---|---|
   | `src/app/(tabs)/index.tsx` | 首页 | 本轮只做骨架 + 空态 |
   | `src/app/(tabs)/add.tsx` | 上架 Add | 本轮只做骨架 + 空态 |
   | `src/app/(tabs)/remove.tsx` | 下架 Remove | 本轮只做骨架 + 空态 |
   | `src/app/(tabs)/sell.tsx` | 售卖 Sell | 占位页，显示「规划中」 |
   | `src/app/(tabs)/settings.tsx` | 设置 Settings | 本轮只做骨架 |

   术语保留中英并列（「上架 Add」「下架 Remove」「售卖 Sell」「设置 Settings」），与原型一致。

2. 底部栏样式按 `tokens.ts`：底色走 `surface`/`line` 描边，选中态用 `green`（`#187653`），未选中用 `muted`（`#78847e`）；最小可触区 ≥ 44。
3. 删掉模板自带的 `explore.tsx` 及其引用；不要留 Welcome / 模板欢迎内容。
4. 建 `src/components/EmptyState.tsx`（props: `message`，可选 `icon`），供四个骨架页复用。
5. 页面底色 `paper`，卡片 `surface`，圆角/间距一律取 token，**组件内禁止硬编码色值**。

**不要做**

- 不接后端、不加数据库调用
- 不实现扫码、容器创建、上架/下架流程（那是 Phase 2/3）
- 不动 `app.json` 的 iOS 配置（bundleId `com.stevenli2007.lastcall`、相机权限文案已配好）
- 不新增依赖（除非确有必要，先说明再加）

## 4. 完成标准（自验收后再报完成）

- `npx tsc --noEmit` 通过（在 `apps/mobile` 下）
- 5 个 tab 都能切换，标题与选中态正确
- 每个骨架页有明确的空态文案，不是白屏
- 没有残留模板文件引用

## 5. 交付方式

- **窄路径** `git add`，只加本次改动的文件；commit 后用 `git status` 确认工作区干净
- **不要 `git push`** —— 我来推
- commit message 用 `feat(T1.1): ...`，正文说明做了什么、哪些没做

## 6. 完成后汇报格式

结论先行，然后 Done / Pending 表格，附需要在我本机终端执行的命令（如 `npx expo run:ios -d "iPhone 17"`）。
