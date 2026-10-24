# LastCall 技术选型（TECHSTACK）

**状态：** Locked
**主原则：** **零第三方依赖。** 只用 Apple 官方框架。仓库中不出现 Package Dependencies（SPM / CocoaPods），不出现任何非 Apple 的网络 SDK。

---

## 1. 环境与版本

| 项 | 值 | 备注 |
|---|---|---|
| Xcode | **27.1** (Build 27A9275) | 已安装，`/Applications/Xcode.app` |
| Swift | **6.4** (swiftlang-6.4.0.34.1) | |
| SwiftUI | Xcode 27 内置版本 | |
| Deployment Target | **iOS 17.0+** | SwiftData 的下限。机器名/downloads 不受此限 |
| 目标设备 | Steven 本人 iPhone | iOS 版本满足 iOS 15.4+ 的扫码门槛 |
| Mac 架构 | Apple Silicon (arm64) | 无需 Rosetta |

> Deployment Target 若 Xcode 27 不允许低至 17.0，则取其允许的最低值；**不要为了追新把 target 抬高**，那会无谓地缩小可用设备范围。

---

## 2. 技术栈总览

| 层 | 选型 | Apple 官方 | 用途 |
|---|---|---|---|
| UI | **SwiftUI** | ✅ | 全部界面 |
| 数据持久化 | **SwiftData** (`@Model` / `@Query`) | ✅ | 替代后端，**本地存储** |
| 条码扫描 | **VisionKit `DataScannerViewController`** | ✅ | 上架 / 下架扫码，设备端离线 |
| 相机桥接 | `UIViewControllerRepresentable` | ✅ | 把 VisionKit 塞进 SwiftUI |
| 日期 OCR（P2 可选） | **Vision `VNRecognizeTextRequest`** | ✅ | 识别包装上的生产日期，仍需人工核对 |
| 图标 | **SF Symbols** | ✅ | 替代原型中使用的 emoji |
| 偏好存储 | `@AppStorage` | ✅ | 仅用于极少量 UI 偏好（如首次启动标记） |
| 构建 / 签名 | Xcode + 免费 Apple ID Personal Team | ✅ | 侧载到真机 |

**明确不引入：**
- ❌ Firebase / Supabase / CloudKit / Cloudflare Workers — demo 无需后端
- ❌ Alamofire / Kingfisher / SnapKit — 无此需求
- ❌ ZXing / ZBar / html5-qrcode — 这是 Web 方案才需要的，原生不需要
- ❌ 任何 Swift Package

---

## 3. 关键决策记录（ADR）

### ADR-001：交付原生 iOS App，而非 Web / PWA

**决策：** 做 SwiftUI 原生 App，侧载到 iPhone。

**背景：** CodeX 交付的参考原型是 HTML。曾考虑在此基础上做移动端 Web App。

**理由：**
1. **扫码在原生方案里是免费的。** VisionKit `DataScannerViewController` 是 Apple 官方、设备端离线、几十行代码。而 Web 方案在 iOS Safari 上**没有** `BarcodeDetector` API，必须引第三方库（ZXing），且必须跑在 HTTPS 上（iOS Safari 在非 HTTPS 下拒绝 `getUserMedia`）。
2. **日期 OCR 同理。** Vision 框架设备端离线可用；Web 方案几乎只能调云端。
3. 用户明确要求"只要苹果官方提供的"，原生方案恰好是 100% 官方。
4. 黑客松线下演示，真机 App 的观感和可信度高于网页。

**代价：** 需要打通 Xcode 签名链路（这是当前最大的未验证风险），且不掌握 SwiftUI。

---

### ADR-002：数据层用 SwiftData 本地持久化，不接后端

**决策：** SwiftData 本地存储，无服务器、无账号体系。

**理由：**
1. demo 是单人单机使用，云同步零收益。
2. 接 Supabase 需要额外处理 Auth + RLS，保守 1.5–2h，而这时间必须留给核心链路。
3. SwiftData 天然解决"杀掉 App 重开数据还在"这个必过的验收点。
4. 全部 Apple 官方，符合零依赖原则。

**代价：** PRD 验收标准 8（跨门店数据隔离）本轮 Deferred。数据模型中已预留 `Store` 外键，后续接入认证层不需要重构。

---

### ADR-003：跳过登录 —— ⚠️ 已于 2026-10-24 被 **ADR-007** 修订

> **新的决定以 ADR-007 为准**：H7 增加「假登录页」（手机号 + 密码 UI，无账号系统）。
> 下方正文保留，仅作决策沿革记录，**不要再按它执行**。

**决策：** MVP 不实现登录页与身份认证。

**理由：** 单人单机 demo 场景下纯属负收益 —— 每次演示都要走一遍登录流程，且消耗约 1.5h 开发时间。`Store` 实体在启动时 seed 一个默认门店，所有数据归属它。

**还原路径：** 后续只需加 Auth 层 + 把 `@Query` 加上门店谓词，数据层无需改动。

---

### ADR-004：移除「售卖 Sell」

**决策：** 移除原型中的 Sell 导航与页面。

**理由：** PRD §6 明确将售卖列为"暂不包含"，保留入口会造成 scope 表述与实际不符，容易被评委质疑。

### ADR-005：上架流程拆出 `AddItemViews.swift`（第 6 个文件）

**决策：** H3 的上架表单单独放进 `AddItemViews.swift`，不塞进 `ContainerViews.swift`。

**背景：** H2 结束时 `ContainerViews.swift` 已达 400 行（CR-1.2 上限），而上架表单预计还要 ~130 行，塞进去必然超限。Steven 于 2026-10-24 13:14 选定本方案。

**理由：**
1. **上架是一条独立的用户流程**（选格 → 扫码 → 日期 → 保质期 → 预览 → 写入），与「容器浏览」不是同一件事，单独成文件更好读。
2. 符合 CODINGRULES §1「**不按技术层横切、只按功能模块竖切**」—— 这是按流程竖切，不是按 View / ViewModel 横切。
3. 不违反「严格 5 个文件」的初衷：该约束是为了防止碎片化，不是为了凑数字。文件数仍远少于常规 SwiftUI 项目。

**代价：** 文件数 5 → 6。本文件与 `CODINGRULES.md` 已同步登记。

---

### ADR-006：H7 文件数 6 → 9（✅ Steven 2026-10-24 16:44 批准）

**决策：** H7 优化阶段新增 / 拆分 3 个文件：`ContainerShelfView.swift`、`LoginViews.swift`、`SellViews.swift`。

**背景：** `ContainerViews.swift` 已 397 行贴上限，而正视图柜体渲染（ADR-005 之后的第 1 项优化）预计还要 ~200 行；登录页与临期专区各自是独立模块。

**理由：**
1. 仍是**按功能模块竖切**，不是按 View / ViewModel 横切 —— 符合 CODINGRULES §1。
2. 单文件 **400 行硬上限不变**，分区（MARK + Ctrl+6）习惯不变。
3. 总文件数 9 个、约 3000 行，对一个 SwiftUI 项目仍属精简。

**代价：** 文件数 6 → 9。`CODINGRULES.md` 与本文档将在 Steven 批准后同步更新。

---

### ADR-007：登录页回归（假登录，无账号系统）

**决策：** H7 增加登录页：手机号（11 位校验）+ 密码（≥6 位），校验通过即进入主界面，**不存储任何账号数据**。设置页提供「退出登录」。

**背景：** Steven 2026-10-24 16:07 提出需求。ADR-003 原本以「每次演示都要走一遍登录」为由砍掉登录 —— 但评委第一眼看到的就是登录页，**它是产品完成度的信号**，与真实身份认证是两件事。

**理由：**
1. **假登录 ≠ 身份认证**：纯 UI，零后端、零凭据存储，`@AppStorage` 记住已登录状态即可反复演示。
2. 登录页天然是「语言切换」与「店主 / 顾客角色」的落点（H7 第 3、7 项）。
3. 演示节奏不受影响：登录一次后杀 App 不再重登，需要时可现场退出重登展示。

**代价：** 约 0.75h + 一个新文件（`LoginViews.swift`，见 ADR-006）。真实账号体系仍是 Deferred，对外如实说明。

---

## 4. 项目结构

```
LastCall/
├── LastCall.xcodeproj
└── LastCall/
    ├── Info.plist                 仅含相机权限说明
    └── App/
        ├── LastCallApp.swift
        ├── Models.swift
        ├── ContentView.swift
        ├── ContainerViews.swift
        ├── AddItemViews.swift      ← H3 新增（见 ADR-005）
        └── ScanViews.swift
```

**严格 6 个 Swift 文件**（原为 5 个，`AddItemViews.swift` 于 H3 按 ADR-005 登记）。新增文件需先更新 `CODINGRULES.md` 与本文档。

`Info.plist` 必需项：
- `NSCameraUsageDescription` — "用于扫描商品条码以记录和下架商品"

---

## 5. 依赖矩阵

| 依赖 | 来源 | 版本约束 | 备注 |
|---|---|---|---|
| SwiftUI.framework | Apple | 随 Xcode | |
| SwiftData.framework | Apple | iOS 17+ | |
| VisionKit.framework | Apple | iOS 15.4+ (DataScanner) | 需 import VisionKit |
| Vision.framework | Apple | iOS 13+ | 仅 OCR 用，P2 |

**总计：4 个系统框架，0 个第三方包。**

---

## 6. 风险登记

| # | 风险 | 影响 | 缓解 |
|---|---|---|---|
| R1 | Xcode 免费签名链路未打通 | **致命** — 无法上真机 | H0 阶段限时 45 分钟；超时走 Fallback（见 ROADMAP §5） |
| R2 | SwiftUI 零基础导致 UI 返工 | 高 | 我生成全量代码，Steven 只负责点 Run 与验收；采用 Declarative 简单控件，避免复杂自绘 |
| R3 | SwiftData 热重载期的数据冲突 | 中 | 演示前 Clean Build Folder + 重装 App 一次；避免使用 CloudKit 同步开关（务必保持关闭） |
| R4 | 7 天签名过期 | 中 | 演示当天进入 □ Settings → 检查描述文件；必要时连 Xcode 一键重签 |
| R5 | 单个 Swift 文件过大导致 SwiftUI Preview 卡顿 | 中 | 拆分上限 400 行 / 文件（见 CODINGRULES） |
| R6 | VisionKit 在真机首次运行需要权限弹窗 | 低 | Info.plist 说明文案已备；UI 提供手动输入兜底 |
