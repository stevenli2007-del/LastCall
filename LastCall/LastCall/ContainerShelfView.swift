//
//  ContainerShelfView.swift
//  LastCall
//
//  柜体正视图：把容器画成一台真的设备 ——
//  冰柜 = 便利店玻璃门冷柜（铝框 + 竖门把手 + 玻璃层板 + 灯带 + 底脚）；
//  货架 = 便利店货架（立柱 + 木层板 + 顶部价签条）。
//  商品按纵深前后叠放成瓶身造型，临期 / 过期的位置码用醒目徽章标出（H7 优化第 1 项）。
//
//  只负责渲染，不做任何数据写入。
//

import SwiftUI
import SwiftData

// MARK: - Location Badge

/// 位置码徽章 —— 全局统一的视觉锚点（H7 §1.3）
/// 黄底黑字 = 临期，红底白字 = 过期，灰底 = 正常。首页 / 货架 / 下架三处同款
struct LocationBadge: View {
    let code: String
    let status: ItemStatus
    var prominent: Bool = false

    var body: some View {
        Text(code)
            .font(.system(size: prominent ? 15 : 12, weight: .bold).monospacedDigit())
            .foregroundStyle(foreground)
            .padding(.horizontal, prominent ? 10 : 7)
            .padding(.vertical, prominent ? 5 : 3)
            .background(background, in: .capsule)
    }

    private var background: Color {
        switch status {
        case .normal: return Color(hex: 0xE7EBE5)
        case .near: return .statusNearBG
        case .expired: return .statusExpiredBG
        }
    }

    private var foreground: Color {
        switch status {
        case .normal: return Color(hex: 0x5A6B62)
        case .near: return .statusNearFG
        case .expired: return .statusExpiredFG
        }
    }
}

// MARK: - Views

/// 一台设备的正视图。点任意一格（货位）→ 打开该格面板
struct ShelfView: View {
    let container: Container
    let today: Date
    let nearDays: Int
    var focusCell: Int?
    let onSelect: (Int) -> Void

    private var isFridge: Bool { container.type == .fridge }
    private var rows: Int { max(1, container.rows) }
    private var cols: Int { max(1, container.columns) }

    var body: some View {
        VStack(spacing: 0) {
            signBoard
            cabinet
            feetBar
        }
    }

    // MARK: 顶部价签条

    private var signBoard: some View {
        HStack(spacing: 6) {
            Image(systemName: container.type.symbolName)
                .font(.caption2)
            Text(container.name)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
            Spacer(minLength: 0)
            Text("\(rows) × \(cols)")
                .font(.caption2.monospacedDigit())
        }
        .foregroundStyle(isFridge ? .white : Color(hex: 0x5C4630))
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(isFridge ? Color(hex: 0x3E5A70) : Color(hex: 0xEFE3C8),
                    in: .rect(cornerRadius: 10, style: .continuous))
        .padding(.bottom, 6)
    }

    // MARK: 柜体

    private var cabinet: some View {
        ZStack(alignment: .topTrailing) {
            interior
                .padding(isFridge ? 6 : 8)
                .background(frameColor)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(frameBorder, lineWidth: 1)
                }

            if isFridge {
                Capsule()
                    .fill(Color(hex: 0x93A8B6))
                    .frame(width: 6, height: 58)
                    .padding(.trailing, 12)
                    .padding(.top, 34)
            }
        }
    }

    /// 内部：灯带 + 逐层货架 + 玻璃反光
    private var interior: some View {
        ZStack(alignment: .top) {
            interiorColor

            VStack(spacing: 0) {
                if isFridge {
                    Capsule()
                        .fill(Color.white.opacity(0.85))
                        .frame(height: 3)
                        .padding(.horizontal, 26)
                        .padding(.top, 8)
                }
                ForEach(0..<rows, id: \.self) { level($0) }
            }

            if isFridge {
                Rectangle()
                    .fill(Color.white.opacity(0.10))
                    .rotationEffect(.degrees(-16))
                    .frame(width: 46)
                    .offset(x: -74)
                    .clipped()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// 一层：货位横向排开，底下压一块层板
    private func level(_ row: Int) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(0..<cols, id: \.self) { col in
                    bay(row * cols + col)
                }
            }
            .frame(minHeight: 66, alignment: .bottom)
            .padding(.horizontal, 4)
            .padding(.top, 4)

            board
        }
    }

    /// 冰柜是玻璃层板，货架是木层板
    private var board: some View {
        Group {
            if isFridge {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white.opacity(0.8))
                    .frame(height: 3)
                    .shadow(color: Color(hex: 0x2E4A5E).opacity(0.12), radius: 1, y: 1)
            } else {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(hex: 0xC4A97A))
                    .frame(height: 6)
                    .shadow(color: Color(hex: 0x8A6B3F).opacity(0.22), radius: 1, y: 1)
            }
        }
        .padding(.horizontal, isFridge ? 6 : 2)
    }

    // MARK: 货位

    private func bay(_ cellIndex: Int) -> some View {
        let cellItems = items(in: container, cell: cellIndex)
        let focused = cellIndex == focusCell

        return Button { onSelect(cellIndex) } label: {
            VStack(spacing: 3) {
                Spacer(minLength: 0)
                productRow(cellIndex, cellItems)
                bayFooter(cellIndex, cellItems: cellItems)
            }
            .frame(maxWidth: .infinity, minHeight: 58, alignment: .bottom)
            .padding(.vertical, 3)
            .background(focused ? Color.brandGreen.opacity(0.10) : Color.clear,
                        in: .rect(cornerRadius: 8))
            .overlay {
                // 正常货位不描边 —— 让它读起来是「开放的空间」，只有聚焦 / 需要处理时才亮边
                RoundedRectangle(cornerRadius: 8)
                    .stroke(strokeColor(cellItems: cellItems, focused: focused),
                            lineWidth: focused ? 2 : 1.5)
                    .opacity(focused || needsAttention(cellItems) ? 1 : 0)
            }
        }
        .buttonStyle(.plain)
    }

    /// 商品按纵深前后叠放：depth 1 在最前（最大最亮），越往里越小越淡。
    /// 空格不逐位画虚线，只在整格空时画一个「空位」占位，避免满屏碎虚线
    private func productRow(_ cellIndex: Int, _ cellItems: [Item]) -> some View {
        Group {
            if cellItems.isEmpty {
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundStyle(Color(hex: 0xC9D3D9).opacity(0.7))
                    .frame(height: 26)
                    .padding(.horizontal, 10)
            } else {
                HStack(alignment: .bottom, spacing: -3) {
                    ForEach(cellItems) { item in
                        product(item, depth: item.depthIndex - 1)
                    }
                }
            }
        }
    }

    private func product(_ item: Item, depth: Int) -> some View {
        let itemStatus = status(of: item, today: today, nearDays: nearDays)
        let height = 30 + CGFloat(abs(item.barcode.hashValue % 5)) * 3
        let fade = Double(min(3, depth)) * 0.18

        return ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 5)
                .fill(productColor(itemStatus))
                .frame(width: 18, height: height)
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.white.opacity(0.6))
                .frame(width: 13, height: 8)
                .padding(.top, 7)
        }
        .scaleEffect(1 - CGFloat(min(3, depth)) * 0.06, anchor: .bottom)
        .opacity(1 - fade)
        .offset(y: -CGFloat(min(3, depth)) * 2)
        .zIndex(Double(container.depthCapacity - depth))
    }

    /// 货位底：格子字母 + 需要处理的件的位置码徽章
    private func bayFooter(_ cellIndex: Int, cellItems: [Item]) -> some View {
        let urgent = cellItems.filter { status(of: $0, today: today, nearDays: nearDays) != .normal }
        return VStack(spacing: 2) {
            Text(excelColumnName(cellIndex))
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color(hex: 0x6B7A72))
            if !urgent.isEmpty {
                HStack(spacing: 2) {
                    ForEach(urgent.prefix(2)) { item in
                        LocationBadge(code: item.locationCode,
                                      status: status(of: item, today: today, nearDays: nearDays),
                                      prominent: false)
                            .scaleEffect(0.78)
                    }
                }
            }
        }
    }

    // MARK: 底脚

    private var feetBar: some View {
        HStack(spacing: 0) {
            if isFridge {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(hex: 0x8FA3B0))
                    .frame(height: 7)
            } else {
                HStack(spacing: 22) {
                    Capsule().fill(Color(hex: 0xB09A72)).frame(width: 30, height: 5)
                    Capsule().fill(Color(hex: 0xB09A72)).frame(width: 30, height: 5)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.top, 6)
        .padding(.horizontal, 24)
    }

    // MARK: 配色与判定

    private func needsAttention(_ cellItems: [Item]) -> Bool {
        cellItems.contains { status(of: $0, today: today, nearDays: nearDays) != .normal }
    }

    private func strokeColor(cellItems: [Item], focused: Bool) -> Color {
        if focused { return Color.brandGreen }
        if cellItems.contains(where: { status(of: $0, today: today, nearDays: nearDays) == .expired }) {
            return .statusExpiredFG.opacity(0.6)
        }
        if needsAttention(cellItems) { return .statusNearFG.opacity(0.55) }
        return Color(hex: 0xD3DCD8).opacity(0.9)
    }

    private func productColor(_ status: ItemStatus) -> Color {
        switch status {
        case .normal: return Color(hex: 0xA9C0AE)
        case .near: return Color(hex: 0xEFB155)
        case .expired: return Color(hex: 0xE07A6E)
        }
    }

    private var frameColor: Color { isFridge ? Color(hex: 0xAFC0CC) : Color(hex: 0xE0CFAE) }
    private var frameBorder: Color { isFridge ? Color(hex: 0x8FA3B0) : Color(hex: 0xBFA47A) }
    private var interiorColor: Color { isFridge ? Color(hex: 0xE7F0F5) : Color(hex: 0xF7F1E3) }
}

// MARK: - Previews

#Preview("冷柜 · 便利店玻璃门") {
    let ctx = ModelContext(PreviewSample.container)
    let fridge = try! ctx.fetch(FetchDescriptor<Container>()).first { $0.type == .fridge }
    return ShelfView(container: fridge ?? Container(name: "牛奶冰柜", type: .fridge, rows: 3, columns: 2, depthCapacity: 5),
                     today: Date(),
                     nearDays: 2,
                     focusCell: nil) { _ in }
        .padding()
        .modelContainer(PreviewSample.container)
}

#Preview("货架 · 木层板") {
    let ctx = ModelContext(PreviewSample.container)
    let shelf = try! ctx.fetch(FetchDescriptor<Container>()).first { $0.type != .fridge }
    return ShelfView(container: shelf ?? Container(name: "面包货架", type: .shelf, rows: 2, columns: 3, depthCapacity: 5),
                     today: Date(),
                     nearDays: 2,
                     focusCell: nil) { _ in }
        .padding()
        .modelContainer(PreviewSample.container)
}
