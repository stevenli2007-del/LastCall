# LastCall 编码规则（CODINGRULES）

**适用：** 本项目所有代码。
**优先级：** 与 PRD / DATABASE 冲突时以 PRD / DATABASE 为准；与安全冲突时以本文件为准。

---

## 1. 文件结构：严格 5 个 Swift 文件

> 针对 Steven 的诉求「代码不想分开写，容易乱」——
> 这里的原则是：**不按技术层横切、只按功能模块竖切**。每个文件是一个你能一整段读完的东西，而不是二十个只装一个 struct 的碎片。

```
LastCall/App/
├── LastCallApp.swift      ① App 入口        ≤ 80 行
├── Models.swift           ② 数据 + 全部算法  ≤ 260 行
├── ContentView.swift      ③ 根视图 + 首页 + 设置  ≤ 380 行
├── ContainerViews.swift   ④ 容器详情 + 格子网格 + 上架表单  ≤ 380 行
└── ScanViews.swift        ⑤ 扫码 UI + 下架流程  ≤ 320 行
```

| 规则 | 说明 |
|---|---|
| **CR-1.1** | **不得新增第 6 个 Swift 文件**，除非先在 TECHSTACK.md §4 登记并说明理由 |
| **CR-1.2** | 单文件超过 **400 行**必须拆分或重构，原因：SwiftUI Preview 会显著变卡 |
| **CR-1.3** | 每个文件顶部必须有统一的 `// MARK:` 目录（见 §2） |

### 文件职责边界

| 文件 | 放什么 | **不放什么** |
|---|---|---|
| ① `LastCallApp.swift` | `@main`、ModelContainer 配置、Store seed、scheme/全局外观 | 任何业务代码 |
| ② `Models.swift` | 全部 `@Model`、`enum`、算法（位置/日期/状态）、`AppDate`、`excelColumnName` | 任何 SwiftUI View |
| ③ `ContentView.swift` | TabView、首页各项卡片、设置页、根导航状态 | 容器内部逻辑 |
| ④ `ContainerViews.swift` | 容器创建表单、格子网格、格位弹窗、上架表单 | 条码扫描 UI |
| ⑤ `ScanViews.swift` | VisionKit 封装、扫码 sheet、下架确认 | 数据写入以外的业务逻辑 |

---

## 2. MARK 分区规范

每个文件必须以下列结构组织。`Ctrl + 6` 可以直接按目录跳转 —— **这是解决"乱"的主要手段，比拆文件有效**。

```swift
// MARK: - Models          （仅 Models.swift）
// MARK: - Algorithms      （仅 Models.swift）
// MARK: - Views           （仅 View 文件）
// MARK: - Subviews
// MARK: - Helpers
// MARK: - Previews
```

| 规则 | 说明 |
|---|---|
| **CR-2.1** | 二级注释用 `// MARK: - 名称`（带横线，出现在 Jump Bar），三级用 `// 名称`（不带横线） |
| **CR-2.2** | 每个 `// MARK:` 上方空一行 |
| **CR-2.3** | 同一 MARK 内，相关类型放一起，不许按字母序排 |

---

## 3. 依赖规则

| 规则 | 说明 |
|---|---|
| **CR-3.1** | **零第三方依赖。** 不得添加 Swift Package、CocoaPods、Carthage、二进制 framework |
| **CR-3.2** | 只允许 `import`：`SwiftUI`、`SwiftData`、`VisionKit`、`Vision`、`Foundation` |
| **CR-3.3** | 禁止任何网络请求。App 必须能在飞行模式下完整运行 |
| **CR-3.4** | 若确有必要引入依赖 → **先停下问 Steven**，不得自行决定 |

---

## 4. 数据规则

| 规则 | 说明 |
|---|---|
| **CR-4.1** | **条码一律 `String`。** 禁止 `Int` / `Int64`。前导零必须保留 |
| **CR-4.2** | 日期加减只用 `Calendar.date(byAdding:)`，**禁止 `+ 86400 * n`**（夏令时会错） |
| **CR-4.3** | 日期比较前必须 `Calendar.current.startOfDay(for:)` 归一化 |
| **CR-4.4** | 所有写入必须满足 DATABASE.md §3 的不变量 I1–I6 |
| **CR-4.5** | 删除 Item 必须同时：写 `RemovalRecord` 快照 + 同格后续 `depthIndex -= 1`，三者在**同一 save 事务**内 |
| **CR-4.6** | 禁止在 View 里直接写业务逻辑。View 只做展示与调用 Models.swift 的函数 |

---

## 5. UI 规则

| 规则 | 说明 |
|---|---|
| **CR-5.1** | **不使用 emoji 作为图标或商品图片。** 统一 SF Symbols |
| **CR-5.2** | 配色沿用 `index.html` 已定义的变量（`--green #187653`、`--lime #d6ef72`、`--paper #f5f7f2` 等），保持两版视觉一致 |
| **CR-5.3** | 状态徽章配色严格按 DATABASE.md §4.3 的表格 |
| **CR-5.4** | 不使用 priority-based 复杂 Layout 容器；网格只用 `LazyVGrid` / `Grid` |
| **CR-5.5** | 每个 View 文件底部配 `#Preview`，方便 SwiftUI Canvas 预览（真机出问题时的第一排查手段） |
| **CR-5.6** | 相机权限被拒 / 扫码失败必须有**手动输入兜底**，不得阻断流程 |

---

## 6. 修改规则（Diff First）

> 这是 Bud 生成代码时的硬约束，也是 Steven review 时最省力的地方。

| 规则 | 说明 |
|---|---|
| **CR-6.1** | **Diff First**：只改被指到的那几行，**绝不整段重写函数/文件** |
| **CR-6.2** | 不做「顺手重构」。发现无关问题 → 记下来告诉 Steven，不自动改 |
| **CR-6.3** | **同一文件的多处 Edit 必须串行执行**（并发写同一文件会造成后写覆盖前写，且工具会报告成功 —— 静默数据丢失） |
| **CR-6.4** | 每次改完立刻读回文件或跑一次 build 验证 |
| **CR-6.5** | 写代码时不留 `// ?` 待办注释；有疑问直接问 |

---

## 7. 命名约定

| 对象 | 规则 | 示例 |
|---|---|---|
| View struct | `名词 + View` | `ContainerDetailView`、`ScannerSheet` |
| `@Model` 类 | 单数名词 | `Container`、`Item` |
| 算法函数 | 动词短语 | `excelColumnName(_:)`、`nextSlot(in:preferredCell:)` |
| UI 私有辅助 | 下划线开头或明确 `private` | `private var fillBar: some View` |
| SwiftData 查询 | `@Query private var xxx` | `@Query private var containers: [Container]` |

---

## 8. Git 与提交

| 规则 | 说明 |
|---|---|
| **CR-8.1** | 每完成一个 Roadmap 阶段打一个 commit，message 前缀标明阶段：`[H1] `、`[H2] `… |
| **CR-8.2** | 窄路径 `git add`，commit 后跑 `git status` 确认无意外文件 |
| **CR-8.3** | ⚠️ **从不 `git add .`** —— Xcode 会把 `*.xcodeproj/xcuserdata/` 等本机状态带进去 |
| **CR-8.4** | `.gitignore` 首行必须有 `*.xcuserstate` 与 `xcuserdata/` |

---

## 9. 禁止事项速查

| ❌ 不要 | ✅ 要 |
|---|---|
| 条码用 Int | 条码用 String |
| `date + 86400 * days` | `Calendar.date(byAdding: .day)` |
| emoji 图标 | SF Symbols |
| 新增第 6 个文件 | 先登记再拆 |
| 整段重写文件 | Diff First 只改目标行 |
| 并发 Edit 同一文件 | 串行 |
| 加第三方包 | 先问 |
| 在 View 里写业务逻辑 | 放 Models.swift |
| `git add .` | 窄路径 add |
