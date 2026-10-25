# LastCall 数据模型（DATABASE）

**存储：** SwiftData（本地，SQLite 底层）
**原则：** 所有 `import SwiftData` 的类型集中在 `Models.swift`，UI 文件不直接写查询谓词以外的业务逻辑。

---

## 1. 实体关系

```
Store ──1:N──> Container ──1:N──> Item
  │                                 │
  │                                 └── N:1 ──> RemovalRecord（删除后留档）
  └── nearExpiryDays: Int（门店级临期阈值）
```

简洁起见：`RemovalRecord` 不持有 `Item` 关系（因为 Item 会被删除），而是**快照式冗余**存储当时的关键字段。

---

## 2. 实体定义

### 2.1 Store（门店）

| 字段 | 类型 | 默认 | 说明 |
|---|---|---|---|
| `id` | `UUID` | `.init()` | 主键 |
| `name` | `String` | — | 门店名，如「青禾便利 · 城南店」 |
| `timezoneIdentifier` | `String` | `TimeZone.current.identifier` | 状态判定用本地日历日 |
| `nearExpiryDays` | `Int` | `2` | 临期阈值 N 天 |
| `createdAt` | `Date` | `.now` | |
| `containers` | `[Container]` | `[]` | `@Relationship(deleteRule: .cascade)` |

> MVP 启动时 seed **一个** Store。取出方式：`@Query var stores: [Store]` 取 `.first`。

---

### 2.2 Container（容器）

| 字段 | 类型 | 默认 | 说明 |
|---|---|---|---|
| `id` | `UUID` | `.init()` | |
| `name` | `String` | — | 如「牛奶冰柜」 |
| `type` | `ContainerType` | `.fridge` | `enum: fridge / shelf`（`Codable`） |
| `rows` | `Int` | `3` | 正视图行数。`> 0` |
| `columns` | `Int` | `2` | 正视图列数。`> 0` |
| `depthCapacity` | `Int` | `5` | 每格纵深容量。`> 0` |
| `createdAt` | `Date` | `.now` | |
| `store` | `Store?` | nil | 反向关系 |
| `items` | `[Item]` | `[]` | `.cascade` |

**派生属性（computed，不存储）：**

| 属性 | 类型 | 计算 |
|---|---|---|
| `cellCount` | `Int` | `rows * columns` |
| `totalCapacity` | `Int` | `rows * columns * depthCapacity` |
| `usedCount` | `Int` | `items.count` |
| `fillRatio` | `Double` | `Double(usedCount) / Double(totalCapacity)` |

**UI 图标**：不用 emoji，用 SF Symbols。

| type | SF Symbol |
|---|---|
| `.fridge` | `refrigerator` 或 `thermometer.snowflake` |
| `.shelf` | `square.grid.3x3.fill` 或 `shippingbox` |

---

### 2.3 Item（单件商品）— 核心实体

| 字段 | 类型 | 默认 | 说明 |
|---|---|---|---|
| `id` | `UUID` | `.init()` | |
| `barcode` | **`String`** | — | ⚠️ **必须字符串**，保留前导零。**禁止 `Int`** |
| `name` | `String` | `""` | 选填。空时 UI 显示「未命名商品」 |
| `productionDate` | `Date` | `.now` | 生产日期（归一化到当天 00:00 存储） |
| `shelfLifeDays` | `Int` | `10` | 保质期天数 |
| `cellIndex` | `Int` | `0` | **格子索引（0-based）**，按行优先映射到 A/B/C… |
| `depthIndex` | `Int` | `0` | **纵深序号（0-based）**。UI 显示时 `+1` |
| `createdAt` | `Date` | `.now` | |
| `container` | `Container?` | nil | 反向关系 |
| `isListed` | `Bool` | `false` | 临期专区挂牌标记（H7-6）。带默认值，SwiftData additive 轻量迁移自动处理 |
| `originalPrice` | `Double` | `0.0` | 挂牌划线原价 |
| `salePrice` | `Double` | `0.0` | 临期售价 |

> **H7-6 设计决策：** 挂牌与商品是 1:1 关系，直接用 Item 字段而非新建 `Listing` 模型 ——
> 避免「新增模型类型」触发真机 schema 迁移风险，且少一层注册。原 H7-OPTIMIZATION §6.2 的
> 「生成一条 Listing」按此实现口径修正（Steven 2026-10-24 批准降级方案时未细化到模型层）。

**派生属性：**

| 属性 | 类型 | 计算 |
|---|---|---|
| `expiryDate` | `Date` | `生产日期 + shelfLifeDays 天`（用 `Calendar.date(byAdding:)`，**不要用 `+ 86400*shelfLifeDays`**，夏令时会错） |
| `barcodeSuffix4` | `String` | `String(barcode.suffix(4))`，不足 4 位时返回原串 |
| `locationCode` | `String` | `ExcelColumnName(cellIndex) + "\(depthIndex + 1)"` → 如 `A1`、`B3`、`AA2` |

---

### 2.4 RemovalRecord（下架事件留档）

| 字段 | 类型 | 说明 |
|---|---|---|
| `id` | `UUID` | |
| `barcode` | `String` | 快照 |
| `itemName` | `String` | 快照 |
| `containerName` | `String` | 快照 |
| `locationCode` | `String` | 快照（下架**前**的位置） |
| `productionDate` | `Date` | 快照 |
| `expiryDate` | `Date` | 快照 |
| `removedAt` | `Date` | 下架时间 |

> 为什么用快照而非关系：Item 删除后关系会断，留档会失效。冗余字段在 demo 场景下是最省事的正确解。

---

## 3. 不变量（Invariants）

> 这些约束由写入侧代码保证，**SwiftData 不做数据库级约束**。任何写入必须同时满足：

| # | 不变量 |
|---|---|
| **I1** | 同一容器内，`(cellIndex, depthIndex)` 组合**唯一** |
| **I2** | 每个格子的 `depthIndex` **从 0 连续递增、无空洞**。删除中间项后其后所有项必须 `depthIndex -= 1` |
| **I3** | `0 <= cellIndex < container.rows * columns` |
| **I4** | `0 <= depthIndex < container.depthCapacity` |
| **I5** | Item 必须属于某个 Container（孤儿 Item 不允许） |
| **I6** | `barcode` 允许在同一个 Container 内**重复**；每件按独立实物处理 |

---

## 4. 关键算法

### 4.1 Excel 列名生成（>26 格）

> **这是原型 `index.html` 里的 Bug**：原型用 `String.fromCharCode(65 + ci)`，当 ci ≥ 26 时会输出 `[`、`]` 等符号。必须用下面这个算法。

```swift
/// 格子索引 → Excel 风格列名。cellIndex 0 → "A", 25 → "Z", 26 → "AA", 27 → "AB"
func excelColumnName(_ index: Int) -> String {
    precondition(index >= 0)
    var n = index
    var result = ""
    while true {
        let r = n % 26
        result = String(UnicodeScalar(65 + r)!) + result
        n = n / 26 - 1
        if n < 0 { break }
    }
    return result
}
```

**自检表：**

| index | 输出 |
|---|---|
| 0 | A |
| 1 | B |
| 25 | Z |
| 26 | AA |
| 27 | AB |
| 51 | AZ |
| 52 | BA |

---

### 4.2 过期日期计算

```swift
extension Calendar {
    /// 按日历日加减，自动处理夏令时。禁止用 timeInterval 直接加 86400
    func dateByAddingDays(_ days: Int, to date: Date) -> Date {
        self.date(byAdding: .day, value: days, to: startOfDay(for: date))!
    }
}

/// 生产日期当天为第 0 天：2026-01-01 + 10 天 = 2026-01-11
var expiryDate: Date {
    Calendar.current.dateByAddingDays(shelfLifeDays, to: productionDate)
}
```

---

### 4.3 状态判定

> ⚠️ **必须先把「今天」和「过期日」都归一化到当天 00:00**，否则下午打开 App 会算出偏差一天的结果。

```swift
enum ItemStatus: String { case normal, near, expired }

func status(of item: Item, today: Date, nearDays: Int) -> ItemStatus {
    let cal = Calendar.current
    let t = cal.startOfDay(for: today)
    let e = cal.startOfDay(for: item.expiryDate)
    let days = cal.dateComponents([.day], from: t, to: e).day ?? 0

    if days <= 0 { return .expired }          // today >= expiry
    if days <= nearDays { return .near }
    return .normal
}
```

**边界自检（N = 1，过期日 2026-01-11）：**

| today | days | 状态 |
|---|---|---|
| 2026-01-09 | 2 | 正常 |
| 2026-01-10 | 1 | 临期 |
| 2026-01-11 | 0 | **过期** |
| 2026-01-12 | -1 | 过期 |

**UI 徽章配色（沿用 `index.html`）：**

| 状态 | 背景 | 文字 |
|---|---|---|
| 正常 | `#e9f5ed` | `#34764c` |
| 临期 | `#fff2dd` | `#aa6d1e` |
| 过期 | `#ffebe8` | `#b84f3d` |

---

### 4.4 上架：计算下一个可用位置

```swift
/// 返回下一个空位；格子满则找下一格；全部满返回 nil
func nextSlot(in container: Container, preferredCell: Int) -> (cell: Int, depth: Int)? {
    if let d = nextDepth(in: container, cell: preferredCell) { return (preferredCell, d) }
    for c in 0..<container.cellCount where c != preferredCell {
        if let d = nextDepth(in: container, cell: c) { return (c, d) }
    }
    return nil
}

func nextDepth(in container: Container, cell: Int) -> Int? {
    let used = container.items.filter { $0.cellIndex == cell }.count
    return used < container.depthCapacity ? used : nil
}
```

> 依据 I2：同一格内已有 n 件，则下一个 `depthIndex` 必然是 n。

---

### 4.5 下架：验证 + 删除 + 补位（同一事务）

```swift
func remove(item: Item, scannedBarcode: String, context: ModelContext) throws {
    // 1. 精确比对完整条码。不匹配 → 抛错，绝不修改库存
    guard scannedBarcode == item.barcode else {
        throw RemoveError.barcodeMismatch
    }

    let container = item.container!
    let snapshot = RemovalRecord(...)          // 2. 快照留档（用删除前的位置）

    context.insert(snapshot)                    // 3. 同一 ModelContext 事务内
    context.delete(item)

    // 4. 同格后续商品前移（I2）
    let siblings = container.items
        .filter { $0.cellIndex == item.cellIndex && $0.depthIndex > item.depthIndex }
        .sorted { $0.depthIndex < $1.depthIndex }
    for s in siblings { s.depthIndex -= 1 }

    try context.save()
}
```

---

## 5. Seed 演示数据

> 直接从 `index.html` 移植，保证甲乙两侧的视觉与数据一致。日期全部相对「今天」动态生成，避免隔天失效。

| 容器 | 类型 | rows×cols×depth | 内容 |
|---|---|---|---|
| 牛奶冰柜 | fridge | 3 × 2 × 5 | A1 鲜牛奶（今天-7 天生产，保质 10）／ B1 鲜牛奶（-5，10）／ B2 酸奶（**-15**，14）／ C1 鲜牛奶（-9，10） |
| 面包货架 | shelf | 2 × 3 × 4 | A1 全麦吐司（-2，7）／ B1 牛角包（-3，5） |
| 饮料冷柜 | fridge | 2 × 2 × 6 | 空 |

**说明：** 这组日期配合默认阈值 `N = 2`，开箱即同时呈现「已过期 / 临期 / 正常」三种状态，演示效果好。若因当天日期导致分布不理想，调整 seed 的偏移天数即可。

> **2026-10-24 实际调整：** 酸奶的偏移由 `-11` 改为 `-15`（保质期仍 14 天）。
> 原因：按原值 `-11` + 14 天 = 过期日在今天 +3 天，落「正常」，当天演示看不到「已过期」红色态。
> 改后过期日 = 昨天 → 已过期。首页呈现 **在库 6 / 临期 2 / 过期 1 / 容器 3**。

**Store seed：**「青禾便利 · 城南店」，`nearExpiryDays = 2`。

---

## 6. 迁移策略

SwiftData 的 schema 版本化在 demo 中**不启用**。开发期若改动 `@Model` 字段导致崩溃，处理方式：

```
Xcode → Product → Clean Build Folder (⇧⌘K)
然后删除手机上的 App 重装
```

**不要**在 demo 中引入 versioned schema，那是纯负担。
