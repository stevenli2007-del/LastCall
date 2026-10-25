//
//  SellViews.swift
//  ⑨ 临期专区：把临期 / 过期库存一键挂牌出售，生成美团式商品卡
//
//  数据落在 Item 的三个挂牌字段上（H7-6 决策：挂牌与商品 1:1，不新建 Listing 模型），
//  好处是 SwiftData 只需 additive 轻量迁移，真机旧数据不会受影响。
//

import SwiftUI
import SwiftData

// MARK: - Tab 容器

/// tabItem 一并定义在这里，让根视图只加一行（CODINGRULES §1 的 ⑨ 槽位）
struct SellTab: View {
    var body: some View {
        NavigationStack { SellListView() }
            .tabItem { Label("临期专区", systemImage: "tag.fill") }
    }
}

// MARK: - 临期专区主页

struct SellListView: View {
    @Query private var items: [Item]
    @Query private var stores: [Store]
    @Environment(\.modelContext) private var context
    @State private var target: Item?

    private let today = Date()

    private var nearDays: Int { stores.first?.nearExpiryDays ?? 2 }
    private var listed: [Item] { items.filter(\.isListed) }

    /// 还没挂牌的临期 / 过期商品，最快过期的排最前 —— 这些才是要先清掉的货
    private var candidates: [Item] {
        items.filter { !$0.isListed && status(of: $0, today: today, nearDays: nearDays) != .normal }
            .sorted { $0.expiryDate < $1.expiryDate }
    }

    var body: some View {
        List {
            if !listed.isEmpty {
                Section("在售挂牌") {
                    ForEach(listed) { item in
                        ListingCard(item: item, today: today, nearDays: nearDays,
                                    storeName: stores.first?.name ?? "未初始化门店")
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button("撤销", role: .destructive) { unlist(item) }
                            }
                    }
                }
            }

            if !candidates.isEmpty {
                Section("临期货 · 可挂牌") {
                    ForEach(candidates) { item in
                        HStack(spacing: 10) {
                            LocationBadge(code: item.locationCode,
                                          itemStatus: status(of: item, today: today, nearDays: nearDays))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.displayName).font(.subheadline.weight(.semibold))
                                Text("\(item.container?.name ?? "—") · \(expiryText(item))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            Button("挂牌") { target = item }
                                .buttonStyle(.bordered)
                                .tint(.brandGreen)
                        }
                    }
                }
            }
        }
        .overlay {
            if listed.isEmpty && candidates.isEmpty {
                ContentUnavailableView("暂无临期货",
                                       systemImage: "tag",
                                       description: Text("临期或过期的商品会出现在这里，可一键挂牌出售"))
            }
        }
        .navigationTitle("临期专区")
        .sheet(item: $target) { ListingFormSheet(item: $0) }
    }

    private func expiryText(_ item: Item) -> String {
        let days = daysUntilExpiry(of: item.expiryDate, today: today)
        return days <= 0 ? "已过期 \(abs(days)) 天" : "还剩 \(days) 天"
    }

    private func unlist(_ item: Item) {
        item.isListed = false
        try? context.save()
    }
}

// MARK: - 商品卡

/// 美团式卡片：折后价 + 划线原价 + 折扣标 + 取货位置 + 剩余天数。卡片本身可直接截图分享
struct ListingCard: View {
    let item: Item
    let today: Date
    let nearDays: Int
    let storeName: String

    private var itemStatus: ItemStatus { status(of: item, today: today, nearDays: nearDays) }
    private var daysLeft: Int { daysUntilExpiry(of: item.expiryDate, today: today) }

    /// 几折（四舍五入到整数）；原价未填时不显示
    private var discount: Int {
        guard item.originalPrice > 0 else { return 0 }
        return Int((item.salePrice / item.originalPrice * 10).rounded())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            priceRow
            footer
        }
        .padding(14)
        .background(.background, in: .rect(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color(hex: 0xE3E9E3), lineWidth: 1)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: item.container?.type.symbolName ?? "shippingbox")
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(Color.brandGreen, in: .rect(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 3) {
                Text(item.displayName).font(.headline)
                Text("\(item.container?.name ?? "—") · 取货 \(item.locationCode)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            ShareLink(item: shareText) {
                Image(systemName: "square.and.arrow.up")
            }
            .buttonStyle(.bordered)
        }
    }

    private var priceRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("¥\(item.salePrice.spec)")
                .font(.title2.weight(.bold))
                .foregroundStyle(Color.statusExpiredFG)
            Text("¥\(item.originalPrice.spec)")
                .font(.caption)
                .strikethrough()
                .foregroundStyle(.secondary)

            if discount > 0 {
                Text("\(discount) 折")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.statusNearFG)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.statusNearBG, in: .rect(cornerRadius: 5))
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, 54)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text(daysLeft <= 0 ? "已过期" : "还剩 \(daysLeft) 天")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(statusColor, in: .rect(cornerRadius: 6))
            Text(storeName)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
    }

    private var statusColor: Color {
        switch itemStatus {
        case .normal: return Color.statusNormalFG
        case .near: return Color.statusNearFG
        case .expired: return Color.statusExpiredFG
        }
    }

    /// 分享给顾客的文案：价格 + 取货位置 + 剩余天数，可直接发到微信群
    private var shareText: String {
        let tail = daysLeft <= 0 ? "已过期，尽快取走" : "保质期还剩 \(daysLeft) 天"
        return "【临期特惠】\(item.displayName) ¥\(item.salePrice.spec)（原价 ¥\(item.originalPrice.spec)）\n"
        + "取货：\(storeName) · \(item.container?.name ?? "") \(item.locationCode)\n"
        + "\(tail)，数量有限，先到先得"
    }
}

// MARK: - 挂牌表单

struct ListingFormSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let item: Item

    @State private var originalPrice = 10.0
    @State private var salePrice = 7.0
    @State private var errorMessage: String?

    private var discount: Int {
        guard originalPrice > 0 else { return 0 }
        return Int((salePrice / originalPrice * 10).rounded())
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("商品") {
                    LabeledContent("名称", value: item.displayName)
                    LabeledContent("取货位置", value: "\(item.container?.name ?? "—") \(item.locationCode)")
                    LabeledContent("过期日", value: item.expiryDate.formatted(date: .numeric, time: .omitted))
                }

                Section("定价") {
                    Stepper("原价 ¥\(originalPrice.spec)", value: $originalPrice, in: 0...999, step: 1)
                    Stepper("临期价 ¥\(salePrice.spec)", value: $salePrice, in: 0...999, step: 0.5)
                    if discount > 0 {
                        LabeledContent("折扣", value: "\(discount) 折")
                    }
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(Color.statusExpiredFG)
                    }
                }

                Section {
                    Text("挂牌后商品仍留在原位置（\(item.locationCode)），下架时才真正移出库存。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("挂牌出售")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) { Button("挂牌") { save() } }
            }
        }
    }

    private func save() {
        guard salePrice > 0 else {
            errorMessage = "临期价需大于 0"
            return
        }
        guard originalPrice <= 0 || salePrice <= originalPrice else {
            errorMessage = "临期价（¥\(salePrice.spec)）不能高于原价（¥\(originalPrice.spec)）"
            return
        }
        item.originalPrice = originalPrice
        item.salePrice = salePrice
        item.isListed = true
        try? context.save()
        dismiss()
    }
}

extension Double {
    /// 卡片与表单统一用一位小数，避免 10.0 显示成 10
    var spec: String { formatted(.number.precision(.fractionLength(1))) }
}

// MARK: - Previews

#Preview("临期专区") {
    SellTab()
        .modelContainer(PreviewSample.container)
}

