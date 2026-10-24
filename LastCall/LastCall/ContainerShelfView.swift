//
//  ContainerShelfView.swift
//  LastCall
//
//  柜体正视图：把容器画成一个真的冰柜 / 货架，格位按 rows × columns 真实排布，
//  商品从前往后叠放；临期与过期的位置码用醒目徽章标出（H7 优化第 1 项）。
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

/// 柜体正视图。冰柜走冷色钢面 + 门把手条，货架走暖色木纹 + 层板
struct ShelfView: View {
    let container: Container
    let today: Date
    let nearDays: Int
    var focusCell: Int?
    let onSelect: (Int) -> Void

    private var isFridge: Bool { container.type == .fridge }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            innerBody
        }
        .background(frameColor, in: .rect(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(frameBorder, lineWidth: 1)
        }
    }

    /// 顶部标识条：类型图标 + 名称 + 尺寸；冰柜额外画一条门把手
    private var headerBar: some View {
        VStack(spacing: 6) {
            if isFridge {
                Capsule()
                    .fill(frameBorder.opacity(0.7))
                    .frame(width: 64, height: 4)
            }
            HStack(spacing: 6) {
                Image(systemName: container.type.symbolName)
                    .font(.caption)
                    .foregroundStyle(isFridge ? Color(hex: 0x4A6B85) : Color(hex: 0x8A6B3F))
                Text("\(container.name) · \(container.rows) × \(container.columns)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(headerText)
            }
            .padding(.bottom, 8)
        }
        .padding(.top, 10)
    }

    private var innerBody: some View {
        VStack(spacing: isFridge ? 8 : 6) {
            ForEach(0..<container.rows, id: \.self) { row in
                HStack(spacing: isFridge ? 8 : 6) {
                    ForEach(0..<container.columns, id: \.self) { col in
                        ShelfCompartment(container: container,
                                         cellIndex: row * container.columns + col,
                                         today: today,
                                         nearDays: nearDays,
                                         focused: row * container.columns + col == focusCell,
                                         onSelect: onSelect)
                    }
                }
                if !isFridge && row < container.rows - 1 {
                    shelfBoard
                }
            }
        }
        .padding(10)
        .background(innerColor, in: .rect(cornerRadius: 12))
        .padding(10)
    }

    /// 货架层板：一行底下压一条厚边，读起来像真的隔板
    private var shelfBoard: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(Color(hex: 0xC4A97A))
            .frame(height: 5)
            .shadow(color: Color(hex: 0x8A6B3F).opacity(0.18), radius: 1, y: 1)
    }

    // MARK: 配色

    private var frameColor: Color { isFridge ? Color(hex: 0xDCE6EE) : Color(hex: 0xE6D8BE) }
    private var frameBorder: Color { isFridge ? Color(hex: 0xB9C9D6) : Color(hex: 0xC9B48C) }
    private var innerColor: Color { isFridge ? Color(hex: 0xF4F8FB) : Color(hex: 0xF8F2E5) }
    private var headerText: Color { isFridge ? Color(hex: 0x3E5A70) : Color(hex: 0x7A5E34) }
}

/// 单个格位（隔间）：字母标签 + 占用数 + 从前往后叠放的商品
struct ShelfCompartment: View {
    let container: Container
    let cellIndex: Int
    let today: Date
    let nearDays: Int
    var focused: Bool = false
    let onSelect: (Int) -> Void

    private var cellItems: [Item] { items(in: container, cell: cellIndex) }
    private var label: String { excelColumnName(cellIndex) }
    private var emptySlots: Int { max(0, container.depthCapacity - cellItems.count) }

    /// 该格里是否有需要立刻处理的东西 —— 有就把整个隔间描边加粗
    private var needsAttention: Bool {
        cellItems.contains { status(of: $0, today: today, nearDays: nearDays) != .normal }
    }

    var body: some View {
        Button { onSelect(cellIndex) } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(label)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color(hex: 0x66736B))
                    Spacer(minLength: 0)
                    Text("\(cellItems.count)/\(container.depthCapacity)")
                        .font(.system(size: 9).monospacedDigit())
                        .foregroundStyle(Color(hex: 0xA1AAA4))
                }

                depthStack

                Spacer(minLength: 0)
            }
            .padding(8)
            .frame(minHeight: 96, alignment: .topLeading)
            .background(Color(hex: 0xFBFCFA), in: .rect(cornerRadius: 11))
            .overlay {
                RoundedRectangle(cornerRadius: 11)
                    .stroke(strokeColor, lineWidth: strokeWidth)
            }
            .shadow(color: focused ? Color.brandGreen.opacity(0.3) : .clear, radius: 6, y: 2)
        }
        .buttonStyle(.plain)
    }

    /// 前面的（depth 小）画在最下面、不透明；越往里越淡、越往右缩进，读起来像纵深
    private var depthStack: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(cellItems.reversed()) { item in
                let itemStatus = status(of: item, today: today, nearDays: nearDays)
                LocationBadge(code: item.locationCode,
                              status: itemStatus,
                              prominent: itemStatus != .normal)
                    .padding(.leading, CGFloat(max(0, item.depthIndex - 1)) * 3)
                    .opacity(1.0 - Double(min(4, item.depthIndex - 1)) * 0.12)
            }
            ForEach(0..<emptySlots, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .foregroundStyle(Color(hex: 0xDDE4DC))
                    .frame(height: 18)
            }
        }
    }

    private var strokeColor: Color {
        if focused { return Color.brandGreen }
        if needsAttention { return .statusExpiredFG.opacity(0.55) }
        return Color(hex: 0xE3E9E3)
    }

    private var strokeWidth: CGFloat { focused ? 2 : (needsAttention ? 1.5 : 1) }
}

// MARK: - Previews

#Preview("柜体正视图 · 冰柜") {
    let ctx = ModelContext(PreviewSample.container)
    let fridge = try! ctx.fetch(FetchDescriptor<Container>()).first { $0.type == .fridge }
    return ShelfView(container: fridge ?? Container(name: "空柜", type: .fridge, rows: 2, columns: 3, depthCapacity: 5),
                     today: Date(),
                     nearDays: 2,
                     focusCell: nil) { _ in }
        .padding()
        .modelContainer(PreviewSample.container)
}

#Preview("位置徽章三种状态") {
    HStack(spacing: 10) {
        LocationBadge(code: "A1", status: .normal)
        LocationBadge(code: "B2", status: .near, prominent: true)
        LocationBadge(code: "B3", status: .expired, prominent: true)
    }
    .padding()
}
