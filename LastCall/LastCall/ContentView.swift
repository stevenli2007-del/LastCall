//
//  ContentView.swift
//  LastCall
//
//  根视图（TabView）+ 首页概览 + 设置入口占位。
//  H2 会在这里加「容器」tab，H4 加「下架」tab。
//

import SwiftUI
import SwiftData

// MARK: - Views

struct ContentView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem {
                    Label("首页", systemImage: "house.fill")
                }
        }
    }
}

struct HomeView: View {
    @Query private var stores: [Store]
    @Query private var containers: [Container]
    @Query private var items: [Item]

    private let today = Date()

    // MARK: - Helpers

    private var store: Store? { stores.first }
    private var nearDays: Int { store?.nearExpiryDays ?? 2 }

    private var inStockCount: Int { items.count }
    private var nearCount: Int { count(of: .near) }
    private var expiredCount: Int { count(of: .expired) }
    private var containerCount: Int { containers.count }

    private func count(of target: ItemStatus) -> Int {
        items.filter { status(of: $0, today: today, nearDays: nearDays) == target }.count
    }

    /// 今日提醒：过期 + 临期，按过期日期升序（PRD §5.2）
    private var alertItems: [Item] {
        items
            .filter { status(of: $0, today: today, nearDays: nearDays) != .normal }
            .sorted { $0.expiryDate < $1.expiryDate }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    overviewGrid
                    alertSection
                }
                .padding(16)
            }
            .background(Color.paper.ignoresSafeArea())
            .navigationTitle("临期宝")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Text(store?.name ?? "未初始化门店")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var overviewGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            StatCard(title: "在库商品", value: inStockCount, symbol: "shippingbox.fill", tint: .brandGreen)
            StatCard(title: "临期", value: nearCount, symbol: "clock.badge.exclamationmark.fill", tint: .statusNearFG)
            StatCard(title: "已过期", value: expiredCount, symbol: "exclamationmark.triangle.fill", tint: .statusExpiredFG)
            StatCard(title: "容器", value: containerCount, symbol: "square.grid.2x2.fill", tint: .brandGreen)
        }
    }

    private var alertSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("今日提醒")
                .font(.headline)

            if alertItems.isEmpty {
                ContentUnavailableView {
                    Label("暂无临期商品", systemImage: "checkmark.circle")
                } description: {
                    Text("所有商品均在保质期内")
                }
                .frame(minHeight: 160)
            } else {
                ForEach(alertItems) { item in
                    AlertRow(item: item, today: today, nearDays: nearDays)
                }
            }
        }
    }
}

// MARK: - Subviews

struct StatCard: View {
    let title: String
    let value: Int
    let symbol: String
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(tint)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(value)")
                    .font(.title2.bold())
                    .contentTransition(.numericText())
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(.background, in: .rect(cornerRadius: 14))
    }
}

struct AlertRow: View {
    let item: Item
    let today: Date
    let nearDays: Int

    private var itemStatus: ItemStatus { status(of: item, today: today, nearDays: nearDays) }

    private var containerName: String { item.container?.name ?? "未知容器" }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.container?.type.symbolName ?? "shippingbox")
                .foregroundStyle(Color.brandGreen)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.displayName)
                        .font(.subheadline.weight(.semibold))
                    Text("·\(item.barcodeSuffix4)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Text("\(containerName) \(item.locationCode) · 过期 \(item.expiryDate.formatted(date: .numeric, time: .omitted))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            StatusBadge(status: itemStatus)
        }
        .padding(12)
        .background(.background, in: .rect(cornerRadius: 12))
    }
}

struct StatusBadge: View {
    let status: ItemStatus

    var body: some View {
        Text(status.displayName)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(background, in: .capsule)
    }

    /// 配色严格按 DATABASE.md §4.3
    private var background: Color {
        switch status {
        case .normal: return .statusNormalBG
        case .near: return .statusNearBG
        case .expired: return .statusExpiredBG
        }
    }

    private var foreground: Color {
        switch status {
        case .normal: return .statusNormalFG
        case .near: return .statusNearFG
        case .expired: return .statusExpiredFG
        }
    }
}

// MARK: - Helpers

extension Color {
    init(hex: UInt, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }

    /// 沿用 index.html 原型变量（CR-5.2）
    static let brandGreen = Color(hex: 0x187653)
    static let brandLime = Color(hex: 0xD6EF72)
    static let paper = Color(hex: 0xF5F7F2)

    static let statusNormalBG = Color(hex: 0xE9F5ED)
    static let statusNormalFG = Color(hex: 0x34764C)
    static let statusNearBG = Color(hex: 0xFFF2DD)
    static let statusNearFG = Color(hex: 0xAA6D1E)
    static let statusExpiredBG = Color(hex: 0xFFEBE8)
    static let statusExpiredFG = Color(hex: 0xB84F3D)
}

/// 预览用的内存数据库，带 seed 数据
enum PreviewSample {
    static var container: ModelContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(
            for: Store.self, Container.self, Item.self, RemovalRecord.self,
            configurations: configuration
        )
        let context = ModelContext(container)
        let store = SeedData.makeDefaultStore()
        context.insert(store)
        for c in SeedData.makeDemoContainers() {
            c.store = store
            store.containers.append(c)
            context.insert(c)
        }
        return container
    }
}

// MARK: - Previews

#Preview {
    ContentView()
        .modelContainer(PreviewSample.container)
}
