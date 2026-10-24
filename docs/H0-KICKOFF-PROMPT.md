# H0 开工提示词

> **用法：** 复制下方代码块内的**全部内容**，粘贴到新对话里发送即可。

````
Bud，我们开始 Cal Hacks 项目 LastCall（临期宝）的开发，现在做 H0 阶段。

## 第一步：先读这 6 份文件（不要跳过，按顺序）
1. /Users/youchengli/Desktop/LastCall/PRD.md                      产品需求 v2.0（最高优先级）
2. /Users/youchengli/Desktop/LastCall/docs/ROADMAP.md             重点读 §0 和 §2 的 H0
3. /Users/youchengli/Desktop/LastCall/docs/CODINGRULES.md         编码规则，硬约束
4. /Users/youchengli/Desktop/LastCall/docs/DATABASE.md            数据模型与算法
5. /Users/youchengli/Desktop/LastCall/docs/TECHSTACK.md           技术选型与 ADR
6. /Users/youchengli/Desktop/LastCall/.workbuddy/memory/MEMORY.md  项目长期记忆（含必须记住的事实）

可选参考：/Users/youchengli/Desktop/LastCall/index.html 是 UI 视觉基准，但它有 5 个已知 bug，
**不要照抄它的 addToContainer 格子命名逻辑**（详见下面「已知雷区」）。

## 项目一句话
便利店临期商品管理 App：给每件商品记录 条码 / 生产日期 / 保质天数 / 三维物理位置
（容器 → 正视图格子 rows×cols → 纵深序号），实时派生临期状态，扫码验证后下架并自动补位。

## 已经锁定、不要再讨论的决策
- 交付：**iOS 原生 App**，Xcode + 免费 Apple ID Personal Team 侧载到我本人的 iPhone。
  不上架 App Store、不做 Android。
- **零第三方依赖**：只用 SwiftUI / SwiftData / VisionKit / Vision / Foundation。禁止加 Swift Package。
- **无后端**：SwiftData 本地持久化，必须能在飞行模式下完整跑通。
- **跳过登录**：数据层保留 Store 实体并 seed 一个默认门店，不做认证。
- **移除「售卖 Sell」**：PRD 里已删除，界面不要出现这个入口。
- 生产日期 OCR 是 P2，H0–H4 阶段不要碰。

## 环境现状（我已实测，不用重复查）
- Xcode 27.1（Build 27A9275），Swift 6.4，Apple Silicon arm64，已安装 ✓
- iPhone「开发者模式」**已开启** ✓
- ⚠️ 上次查到 `security find-identity -v -p codesigning` 返回 **0 valid identities**，
  `~/Library/MobileDevice/Provisioning Profiles/` 不存在 → Apple ID 大概率还没加进 Xcode。

## H0 的目标
**让一个新建的空白 SwiftUI App，通过 USB 跑到我的 iPhone 上，能打开不闪退。**
这一步不过，后面全部是沉没成本。

## 你要做的第一件事：验证
先跑：
    security find-identity -v -p codesigning

然后分两种情况：
- **仍然 0 valid identities** → 说明 Apple ID 没加进 Xcode。
  这时候**不要建项目**，先用最简短的步骤指引我完成：
  Xcode → Settings(⌘,) → Accounts → 左下角 + → Apple ID 登录 → 选中账号后右侧出现「你的名字 (Personal Team)」。
  我做完会告诉你，你再跑一次上面的命令确认。
- **>= 1 valid identity** → Personal Team 已就绪，直接进入建项目步骤。

## 建项目的规范（严格照这个，别自由发挥）
Xcode → File → New → Project → iOS → App：
- Product Name：`LastCall`
- Interface：**SwiftUI**
- Language：**Swift**
- Storage：**SwiftData**（勾上，让 Xcode 自动生成 ModelContainer 样板）
- ⚠️ **不要勾 Include Tests**
- 项目保存到：`/Users/youchengli/Desktop/LastCall/`

然后：
1. 左侧 Navigator 最顶上点蓝色项目图标（看不到 Navigator 就按 ⌘0）
2. 中间编辑器区点 **Signing & Capabilities** 标签
3. ⚠️ 注意：PROJECT 和 TARGET 两处都有这个标签，**以 TARGETS → LastCall 那个为准**
4. 勾 **Automatically manage signing**
5. **Team** 下拉框选 `我的名字 (Personal Team)`
6. 确认 Team 下方的黄字警告**全部消失**
7. USB 连 iPhone → 顶部设备选择器选我的 iPhone → ⌘R

## H0 完成的定义（全部达成才算过）
- [ ] Xcode 无红色错误
- [ ] 手机桌面上出现 App 图标
- [ ] 点开能运行，不闪退
- [ ] 若提示「未受信任的开发者」→ 手机 设置 → 通用 → VPN与设备管理 → 信任
- [ ] 你跑一遍 `security find-identity -v -p codesigning` 把输出贴给我当证据

## 熔断规则（重要）
如果 H0 卡住超过 **45 分钟**（签名报错 / 设备不识别 / Apple ID 反复失败），
**立刻停下来告诉我，不要死磕**。我们走 ROADMAP §5 的降级决策。
昨天我已经在 Xcode 环境上损失过一次时间，不要重复这个模式。

## 硬约束（违反即返工）
- **严格 5 个 Swift 文件**：LastCallApp.swift / Models.swift / ContentView.swift /
  ContainerViews.swift / ScanViews.swift。不得新增第 6 个，单文件 ≤ 400 行。
  这是 Steven 明确要求的：代码不要过度拆分，靠 `// MARK: -` 分区 + Ctrl+6 导航来找，
  不是靠继续拆文件。
- **条码必须是 String**，禁止 Int（前导零会丢）。
- 日期加减只用 `Calendar.date(byAdding:)`，禁止 `+ 86400 * n`（夏令时会错）。
- **同一文件的多处编辑必须串行**（并发写会静默覆盖，工具还会报成功）。
- Diff First：只改要改的那几行，不顺手重构。
- 每个 View 底部配 `#Preview`。

## 已知雷区（这些是原型 index.html 的 bug，写码时不要重蹈覆辙）
1. 格子标签公式不一致：原型用 `65+floor(ci/cols)+(ci%cols+1)` 生成 "A1/B1"，
   和全局 `65+ci` 的 "A/B/C" 打架。**唯一正确算法在 DATABASE.md §4.1 的 excelColumnName。**
2. `String.fromCharCode(65+ci)` 在 ci≥26 会输出 `[`、`]` —— 超过 26 格必须按 Excel 列名延伸。
3. 原型数据全在内存，刷新即丢 —— 我们不会，用 SwiftData。
4. 原型详情页下架后不重绘 —— 我们要重绘。

## 协作方式（按这个来）
- 中文简体回答。结论先行，推导后置。
- 高精简：先给「当前进度摘要」，再给 Done / Pending 表格，用 ✅ / ⚪ 标状态。
- 每完成一个阶段给一份 Done Report：做了什么、怎么验证的、下一步是什么。
- **要有证据**：说某个调试通过了，就把命令输出贴出来，不要只说"应该没问题"。
- 不可逆操作前必须先问我。超出当前 scope 的事情先停下问。
- **不要 git push**。commit 用窄路径 git add，commit 后跑 git status，push 由我手动做。
- H0 完成后，去更新 /Users/youchengli/Desktop/LastCall/docs/ROADMAP.md 的 §6 阶段完成记录表。

现在开始：先跑 `security find-identity -v -p codesigning`，然后告诉我结果。
````
