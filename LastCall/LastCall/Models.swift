//
//  Models.swift
//  LastCall
//
//  数据模型 + 全部业务算法。
//  本文件不含任何 SwiftUI View（见 CODINGRULES §1 文件职责边界）。
//  字段与算法依据 docs/DATABASE.md，不自行发明。
//

import Foundation
import SwiftData

// MARK: - Models

enum ContainerType: String, Codable, CaseIterable, Identifiable {
    case fridge
    case shelf

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fridge: return "冰柜"
        case .shelf: return "货架"
        }
    }

    var symbolName: String {
        switch self {
        case .fridge: return "thermometer.snowflake"
        case .shelf: return "shippingbox"
        }
    }
}

@Model
final class Store {
    var id: UUID
    var name: String
    var timezoneIdentifier: String
    var nearExpiryDays: Int
    var createdAt: Date
    @Relationship(deleteRule: .cascade, inverse: \Container.store) var containers: [Container] = []

    init(name: String = "未命名门店",
         timezoneIdentifier: String = TimeZone.current.identifier,
         nearExpiryDays: Int = 2) {
        self.id = UUID()
        self.name = name
        self.timezoneIdentifier = timezoneIdentifier
        self.nearExpiryDays = nearExpiryDays
        self.createdAt = .now
        self.containers = []
    }
}

@Model
final class Container {
    var id: UUID
    var name: String
    var type: ContainerType
    var rows: Int
    var columns: Int
    var depthCapacity: Int
    var createdAt: Date
    var store: Store?
    @Relationship(deleteRule: .cascade, inverse: \Item.container) var items: [Item] = []

    init(name: String,
         type: ContainerType = .fridge,
         rows: Int = 3,
         columns: Int = 2,
         depthCapacity: Int = 5) {
        self.id = UUID()
        self.name = name
        self.type = type
        self.rows = max(1, rows)
        self.columns = max(1, columns)
        self.depthCapacity = max(1, depthCapacity)
        self.createdAt = .now
        self.store = nil
        self.items = []
    }

    // 派生属性（不存储）

    var cellCount: Int { rows * columns }
    var totalCapacity: Int { rows * columns * depthCapacity }
    var usedCount: Int { items.count }
    var fillRatio: Double { totalCapacity == 0 ? 0 : Double(usedCount) / Double(totalCapacity) }
}

@Model
final class Item {
    var id: UUID
    /// ⚠️ 条码必须是 String，禁止 Int —— 前导零会丢（CR-4.1）
    var barcode: String
    var name: String
    var productionDate: Date
    var shelfLifeDays: Int
    /// 格子索引，0-based，按行优先映射到 A/B/C…
    var cellIndex: Int
    /// 纵深序号，0-based，UI 显示时 +1
    var depthIndex: Int
    var createdAt: Date
    var container: Container?

    // 临期专区挂牌（H7-6）。三者都有默认值 —— SwiftData 会自动做 additive 轻量迁移，真机旧数据不受影响
    var isListed = false
    var originalPrice = 0.0     // 划线原价
    var salePrice = 0.0         // 临期售价

    init(barcode: String,
         name: String = "",
         productionDate: Date,
         shelfLifeDays: Int = 10,
         cellIndex: Int = 0,
         depthIndex: Int = 0) {
        self.id = UUID()
        self.barcode = barcode
        self.name = name
        self.productionDate = Calendar.current.startOfDay(for: productionDate)
        self.shelfLifeDays = shelfLifeDays
        self.cellIndex = cellIndex
        self.depthIndex = depthIndex
        self.createdAt = .now
        self.container = nil
    }

    // 派生属性（不存储）

    /// 生产日期当天算第 0 天：2026-01-01 + 10 天 = 2026-01-11
    var expiryDate: Date {
        Calendar.current.dateByAddingDays(shelfLifeDays, to: productionDate)
    }

    var barcodeSuffix4: String { barcodeSuffix(of: barcode) }

    /// 如 A1、B3、AA2
    var locationCode: String {
        excelColumnName(cellIndex) + "\(depthIndex + 1)"
    }

    var displayName: String {
        name.isEmpty ? "未命名商品" : name
    }
}

@Model
final class RemovalRecord {
    var id: UUID
    var barcode: String
    var itemName: String
    var containerName: String
    var locationCode: String
    var productionDate: Date
    var expiryDate: Date
    var removedAt: Date

    init(barcode: String,
         itemName: String,
         containerName: String,
         locationCode: String,
         productionDate: Date,
         expiryDate: Date,
         removedAt: Date = .now) {
        self.id = UUID()
        self.barcode = barcode
        self.itemName = itemName
        self.containerName = containerName
        self.locationCode = locationCode
        self.productionDate = productionDate
        self.expiryDate = expiryDate
        self.removedAt = removedAt
    }
}

// MARK: - Algorithms

enum ItemStatus: String, Codable, CaseIterable {
    case normal
    case near
    case expired

    var displayName: String {
        switch self {
        case .normal: return "正常"
        case .near: return "临期"
        case .expired: return "过期"
        }
    }
}

enum AddItemError: LocalizedError {
    case containerFull

    var errorDescription: String? {
        switch self {
        case .containerFull: return "容器已装满，没有空位"
        }
    }
}

enum RemoveError: LocalizedError {
    case barcodeMismatch
    case missingContainer

    var errorDescription: String? {
        switch self {
        case .barcodeMismatch: return "条码不匹配，库存未做任何修改"
        case .missingContainer: return "该商品不属于任何容器，无法下架"
        }
    }
}

extension Calendar {
    /// 按日历日加减，自动处理夏令时。禁止用 timeInterval 直接加 86400（CR-4.2）
    func dateByAddingDays(_ days: Int, to date: Date) -> Date {
        self.date(byAdding: .day, value: days, to: startOfDay(for: date))!
    }
}

/// 列表与提醒只显示后四位；不足四位时原样返回。上架预览也用它，保证两处口径一致
func barcodeSuffix(of barcode: String) -> String {
    barcode.count > 4 ? String(barcode.suffix(4)) : barcode
}

/// 格子索引 → Excel 风格列名。0 → "A"，25 → "Z"，26 → "AA"，27 → "AB"
/// 原型 index.html 的 `String.fromCharCode(65 + ci)` 在 ci ≥ 26 会输出 `[`、`]`，必须用它替代
func excelColumnName(_ index: Int) -> String {
    precondition(index >= 0, "cellIndex 不能为负")
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

/// 状态判定。比较前必须把今天与过期日都归一化到当天 00:00（CR-4.3），否则午后会差一天
func status(of item: Item, today: Date, nearDays: Int) -> ItemStatus {
    status(ofExpiry: item.expiryDate, today: today, nearDays: nearDays)
}

/// 距过期还有几天，两侧都归一化到当天 00:00（CR-4.3）；≤0 即已过期
func daysUntilExpiry(of expiryDate: Date, today: Date) -> Int {
    let cal = Calendar.current
    return cal.dateComponents([.day], from: cal.startOfDay(for: today),
                              to: cal.startOfDay(for: expiryDate)).day ?? 0
}

/// 判定的唯一实现。上架预览时还没有 Item 实例，也走这里 —— 避免出现第二套写法
func status(ofExpiry expiryDate: Date, today: Date, nearDays: Int) -> ItemStatus {
    let days = daysUntilExpiry(of: expiryDate, today: today)
    if days <= 0 { return .expired }      // today >= expiry
    if days <= nearDays { return .near }
    return .normal
}

/// 该格内下一个可用纵深序号；格子已满返回 nil
///
/// I2 保证格内从 0 连续无空洞，此时「件数」与「最大序号 + 1」相等。
/// 取两者的较大值是防御：万一历史上出现过空洞，也不会把新商品写到一个已被占用的位置。
func nextDepth(in container: Container, cell: Int) -> Int? {
    let indices = container.items.filter { $0.cellIndex == cell }.map(\.depthIndex)
    let next = max(indices.count, (indices.max() ?? -1) + 1)
    return next < container.depthCapacity ? next : nil
}

/// 下一个空位：优先 preferredCell，该格满则顺延找下一格；全部满返回 nil
func nextSlot(in container: Container, preferredCell: Int) -> (cell: Int, depth: Int)? {
    if let d = nextDepth(in: container, cell: preferredCell) { return (preferredCell, d) }
    for c in 0..<container.cellCount where c != preferredCell {
        if let d = nextDepth(in: container, cell: c) { return (c, d) }
    }
    return nil
}

// MARK: - 改规格校验（H7-2）

/// 改小规格会让已有商品「悬空」的一种冲突
enum ResizeConflict: Identifiable {
    case cellRemoved(label: String, count: Int)                   // 新规格没有这一格
    case depthOverflow(label: String, count: Int, newDepth: Int)  // 格子还在，但装不下

    var id: String { message }
    var message: String {
        switch self {
        case .cellRemoved(let l, let n):
            return "\(l) 格还有 \(n) 件，新规格没有这一格"
        case .depthOverflow(let l, let n, let d):
            return "\(l) 格有 \(n) 件，超过新的纵深 \(d)（超出 \(n - d) 件）"
        }
    }
}

/// 改规格前先问一次：返回空 = 可以安全保存。缩小会打破不变量 I1 / I2，
/// 一律**拒绝保存**、不做自动搬家 —— 商品位置是物理事实（H7 §2.3，Steven 2026-10-24 拍板）
func resizeConflicts(in container: Container,
                     rows: Int, columns: Int, depthCapacity: Int) -> [ResizeConflict] {
    let cells = max(1, rows) * max(1, columns)
    let depth = max(1, depthCapacity)
    var out: [ResizeConflict] = []
    for cell in 0..<container.cellCount {
        let n = container.items.filter { $0.cellIndex == cell }.count
        guard n > 0 else { continue }
        if cell >= cells { out.append(.cellRemoved(label: excelColumnName(cell), count: n)) }
        else if n > depth { out.append(.depthOverflow(label: excelColumnName(cell), count: n, newDepth: depth)) }
    }
    return out
}

/// 上架：算下一个空位 → 写入 → save。位置由 nextSlot 决定（不变量 I1 / I3 / I4）
/// 容器全满时抛错，不写入任何数据
@discardableResult
func addItem(barcode: String,
             name: String,
             productionDate: Date,
             shelfLifeDays: Int,
             to container: Container,
             preferredCell: Int,
             context: ModelContext) throws -> Item {
    guard let slot = nextSlot(in: container, preferredCell: preferredCell) else {
        throw AddItemError.containerFull
    }
    let item = Item(barcode: barcode,
                    name: name,
                    productionDate: productionDate,
                    shelfLifeDays: shelfLifeDays,
                    cellIndex: slot.cell,
                    depthIndex: slot.depth)
    item.container = container
    container.items.append(item)
    context.insert(item)
    try context.save()
    return item
}

/// 下架：验证 → 留档 → 删除 → 同格后续前移。四步在同一事务内（CR-4.5 / 不变量 I2）
func remove(item: Item, scannedBarcode: String, context: ModelContext) throws {
    guard scannedBarcode == item.barcode else { throw RemoveError.barcodeMismatch }
    guard let container = item.container else { throw RemoveError.missingContainer }

    let snapshot = RemovalRecord(barcode: item.barcode,
                                 itemName: item.displayName,
                                 containerName: container.name,
                                 locationCode: item.locationCode,
                                 productionDate: item.productionDate,
                                 expiryDate: item.expiryDate)
    context.insert(snapshot)
    context.delete(item)

    let siblings = container.items
        .filter { $0.cellIndex == item.cellIndex && $0.depthIndex > item.depthIndex }
        .sorted { $0.depthIndex < $1.depthIndex }
    for s in siblings { s.depthIndex -= 1 }

    try context.save()
}

// MARK: - Seed

enum SeedData {
    static func makeDefaultStore() -> Store {
        Store(name: "青禾便利 · 城南店", timezoneIdentifier: TimeZone.current.identifier, nearExpiryDays: 2)
    }

    /// 演示容器。日期全部相对「今天」动态生成，避免隔天失效（DATABASE §5）
    ///
    /// 偏差说明：酸奶的生产偏移按 DATABASE §5 原为 -11，调整为 -15（保质期仍 14 天），
    /// 使其过期日落在昨天 —— 演示当天首页能同时呈现「正常 / 临期 / 过期」三态。
    /// Steven 于 2026-10-24 确认。
    static func makeDemoContainers(today: Date = .now) -> [Container] {
        let cal = Calendar.current
        func produced(daysAgo: Int) -> Date { cal.dateByAddingDays(-daysAgo, to: today) }

        let fridge = Container(name: "牛奶冰柜", type: .fridge, rows: 3, columns: 2, depthCapacity: 5)
        // 格式刻意单行：Seed 段行数直接影响 Models.swift 的总行数上限
        fridge.items.append(contentsOf: [
            Item(barcode: "6901028075831", name: "鲜牛奶", productionDate: produced(daysAgo: 7), shelfLifeDays: 10, cellIndex: 0, depthIndex: 0),
            Item(barcode: "6901028075831", name: "鲜牛奶", productionDate: produced(daysAgo: 5), shelfLifeDays: 10, cellIndex: 1, depthIndex: 0),
            Item(barcode: "6901028075862", name: "酸奶", productionDate: produced(daysAgo: 15), shelfLifeDays: 14, cellIndex: 1, depthIndex: 1),
            Item(barcode: "6901028075831", name: "鲜牛奶", productionDate: produced(daysAgo: 9), shelfLifeDays: 10, cellIndex: 2, depthIndex: 0)
        ])

        let shelf = Container(name: "面包货架", type: .shelf, rows: 2, columns: 3, depthCapacity: 4)
        shelf.items.append(contentsOf: [
            Item(barcode: "6901028080001", name: "全麦吐司", productionDate: produced(daysAgo: 2), shelfLifeDays: 7, cellIndex: 0, depthIndex: 0),
            Item(barcode: "6901028080002", name: "牛角包", productionDate: produced(daysAgo: 3), shelfLifeDays: 5, cellIndex: 1, depthIndex: 0)
        ])

        let drinks = Container(name: "饮料冷柜", type: .fridge, rows: 2, columns: 2, depthCapacity: 6)

        return [fridge, shelf, drinks]
    }
}
