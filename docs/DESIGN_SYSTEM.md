# 设计系统与屏幕清单（T0.5）

**状态：** Draft v1.0
**来源：** 仓库根 `index.html` 交互原型
**实现：** `apps/mobile/src/constants/tokens.ts`（唯一 token 来源）

本文档服务于 Roadmap T0.5：把 HTML 原型固化为移动端设计 token 与屏幕清单，
作为 Phase 1 起所有界面的唯一视觉与结构依据。原型本身仍是交互参考，不是生产代码（ADR-001）。

## 1. 设计原则

1. **单一 token 来源**：颜色、圆角、间距、字号一律从 `tokens.ts` 取，组件内禁止硬编码色值。
2. **状态色语义化**：正常 / 临期 / 过期只用 `statusColors`，状态由日期派生，不由人工标记（PRD §3）。
3. **位置优先**：任何商品展示都必须能看到「容器 + 格位 + 纵深序号」（如 牛奶冰柜 A2），这是产品核心价值。
4. **可点性优先**：列表行、格位、商品单元的最小可触区不低于 `layout.minTouchTarget`（44）。
5. **店员场景**：单手持机操作，主操作放在拇指可达区域；字号不低于 `fontSize.meta`（11）。

## 2. 设计 token

### 2.1 颜色

| Token | 值 | 用途 |
|---|---|---|
| `ink` | `#17221e` | 主文字 |
| `muted` | `#78847e` | 次级文字、说明 |
| `paper` | `#f5f7f2` | 页面底色 |
| `line` | `#e7ebe5` | 分隔线、卡片描边 |
| `green` | `#187653` | 主色：主按钮、强调文字 |
| `greenSoft` | `#e7f2eb` | 浅绿底 |
| `greenActive` | `#e8f1e9` | 选中项底色 |
| `greenHover` | `#f2f5ef` | 悬停 / 按下 |
| `greenIcon` | `#edf5ee` | 图标容器底 |
| `lime` | `#d6ef72` | 深色卡上的强调色 |
| `orange` | `#e9a449` | 临期强调 |
| `red` | `#d76c59` | 过期强调 |
| `surface` / `surfaceAlt` | `#ffffff` / `#fbfcf9` | 卡片 / 次级表面 |
| `surfaceDark` | `#193d30` | 深色提醒卡 |
| `onDark` / `onDarkSub` / `onDarkAccent` | `#ffffff` / `#c6d6cf` / `#c7e680` | 深色卡上的文字层级 |
| `track` / `fill` | `#edf1ec` / `#79ae83` | 容量进度条 |
| `focusBorder` / `focusRing` | `#62a477` / `#e9f5eb` | 格位聚焦 |

### 2.2 状态色（`statusColors`）

| 状态 | 背景 | 文字 | 描边 | 文案 |
|---|---|---|---|---|
| `normal` | `#e9f5ed` | `#34764c` | `#d6e7d8` | 正常 |
| `near` | `#fff2dd` | `#a46a1e` | `#f5dfb8` | 临期中 |
| `expired` | `#ffebe8` | `#b84f3d` | `#f2d0c9` | 已过期 |

### 2.3 字号 / 字重

| Token | 值 | 用途 |
|---|---|---|
| `display` | 30 | 页面主标题 |
| `title` | 19 | 容器详情标题 |
| `section` | 15 | 区块标题 |
| `card` | 14 | 卡片标题 |
| `body` | 13 | 正文 |
| `bodySm` | 12 | 次级正文、按钮 |
| `meta` | 11 | 说明文字 |
| `micro` | 10 | 脚注 |
| `badge` | 9 | 状态徽章 |

字重：`regular 400` / `medium 500` / `semibold 600` / `bold 700`。

### 2.4 圆角与间距

圆角：`sm 9`（输入框、小按钮）· `md 11`（主按钮、图标格）· `lg 15`（格位、统计卡）· `xl 17`（卡片）· `pill 999`（徽章）

间距：`xs 4` · `sm 8` · `md 12` · `lg 16` · `xl 22` · `xxl 33`

布局：页面左右内边距 18 · 卡片间距 14 · 最小可触区 44

## 3. 屏幕清单

路由按 Expo Router 文件路由规划。Phase 1 先落地底部导航与骨架，业务数据接后端后再填充。

| # | 屏幕 | 路由 | 原型对应 | 关键元素 | 必须处理的状态 |
|---|---|---|---|---|---|
| 1 | 首页 | `app/(tabs)/index.tsx` | 首页 | 问候语 + 今日日期、4 个统计卡（在库 / 临期 / 已过期 / 存储位置）、今日临期提醒列表、智能提醒深色卡、我的存储位置、存储容器网格 | 加载、无临期商品空态、无容器空态 |
| 2 | 容器详情 | `app/container/[id].tsx` | 容器格位页 | 返回、容器名与规格、正视图格位网格（行 × 列，不画纵深）、格内商品单元（A1–A5）、在库数量、位置说明、状态图例 | 加载、容器不存在、空格位、格位已满 |
| 3 | 格位弹窗 | 组件 `CellSheet` | 格子弹窗 | 格位编码、格内商品清单（名称 / 条码末四位 / 生产日 / 到期日 / 状态）、添加商品、前往下架 | 空格位、格位已满 |
| 4 | 添加商品弹窗 | 组件 `AddItemSheet` | 添加商品弹窗 | 扫码取景框、条码、商品名称（选填）、生产日期（手动 / 相机识别双入口）、预计存储天数、过期日期预览 | 未扫码、相机权限拒绝 → 手动输入、日期识别需人工核对、格位已满 |
| 5 | 上架 | `app/(tabs)/add.tsx` | 上架 Add | 容器名、冰柜 / 货架类型选择、行数、列数、纵深容量、说明文案 | 名称为空、尺寸非法 |
| 6 | 下架 | `app/(tabs)/remove.tsx` | 下架 Remove | 在库商品列表（商品 / 条码末四位 / 位置 / 过期日期 / 状态）、选中下架按钮 | 加载、无在库商品 |
| 7 | 扫码确认下架 | 组件 `RemoveConfirmSheet` | 下架确认弹窗 | 已选商品信息、扫码取景框、应匹配条码末四位、手动输入兜底 | 条码不匹配 → 明确提示且不改库存、相机权限拒绝 |
| 8 | 售卖 | `app/(tabs)/sell.tsx` | 售卖 Sell | 占位说明「规划中」 | 占位 |
| 9 | 设置 | `app/(tabs)/settings.tsx` | 设置 Settings | 临期天数选择（默认 2 天）、门店时区展示、日期识别说明、保存 | 保存成功提示 |
| 10 | 登录 | `app/(auth)/login.tsx` | 原型未覆盖 | 账号登录、退出 | 未登录路由保护、登录失败 |
| 11 | 加载 / 错误边界 | `app/+not-found.tsx` 等 | — | 统一空态、错误态、加载态 | T1.4 统一规范 |

## 4. 复用组件清单

Phase 1 起按此拆分，避免每个屏幕各写一份：

| 组件 | 用途 | 关键 props |
|---|---|---|
| `StatusBadge` | 状态徽章 | `status: FreshnessStatus` |
| `StatCard` | 首页统计卡 | `label / value / footnote / icon` |
| `AlertRow` | 临期提醒行 | `product / location / expiryDate / status` |
| `ContainerTile` | 容器卡片 | `name / kind / rows / columns / capacity / count` |
| `CellGrid` | 正视图格位网格 | `rows / columns / cells / focusedCellId` |
| `UnitChip` | 格内商品单元 | `code（如 A2）/ barcodeLast4 / status` |
| `PrimaryButton` | 主按钮（含 secondary / ghost / danger 变体） | `variant / title / onPress` |
| `EmptyState` | 空态 | `message` |
| `ScanFrame` | 扫码取景框 | `hint` |
| `Toast` | 轻提示 | `message` |

## 5. 文案与本地化

- 界面文案以简体中文为主；产品术语保留中英并列（如「上架 Add」「下架 Remove」），与原型一致。
- 状态文案固定为「正常 / 临期中 / 已过期」，不得出现「过期」「快过期」等第二套说法。
- 条码在界面上默认只显示末四位；完整条码只在扫码核对时使用（PRD §4.4）。

## 6. 待确认

- 是否支持深色模式：MVP 先只做浅色（`userInterfaceStyle: automatic` 保留，后续再适配深色 token）。
- 商品图片 / emoji：原型用 emoji 占位，MVP 沿用，后续再决定是否引入商品图库。
