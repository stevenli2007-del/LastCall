//
//  ContainerViews.swift
//  LastCall
//
//  容器列表 / 新建表单 / 正视图格子网格 / 格位弹窗。
//  格子标签一律走 excelColumnName —— 不用原型的 charCode 公式，它 ci ≥ 26 会输出 `[`（DATABASE §4.1）。
//

import SwiftUI
import SwiftData

// MARK: - Route

/// 跳转参数。`focusItemID` 非空时，详情页高亮该商品所在格子（PRD 验收标准 7）
struct ContainerRoute: Hashable {
    let containerID: UUID
    let focusItemID: UUID?
}

// MARK: - Views

struct ContainerListView: View {
    @Query(sort: \Container.createdAt) private var containers: [Container]
    @Environment(\.modelContext) private var context
    @State private var showingCreate = false

    var body: some View {
        NavigationStack {
            Group {
                if containers.isEmpty {
                    ContentUnavailableView("还没有容器",
                                           systemImage: "square.grid.2x2",
                                           description: Text("点右上角 + 创建冰柜或货架"))
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(containers) { container in
                                NavigationLink(value: ContainerRoute(containerID: container.id,
                                                                     focusItemID: nil)) {
                                    ContainerTile(container: container)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .background(Color.paper.ignoresSafeArea())
            .navigationTitle("容器")
            .navigationDestination(for: ContainerRoute.self) { route in
                ContainerDetailView(route: route)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingCreate = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showingCreate) { ContainerFormSheet(mode: .create) }
        }
    }
}

/// 容器详情：正视图只画 `rows × columns` 个格子，纵深用小色块表示（PRD §5.3）
struct ContainerDetailView: View {
    let route: ContainerRoute
    @Query private var containers: [Container]
    @Query private var stores: [Store]
    @State private var selectedCell: Int?
    @State private var addItemCell: Int?
    @State private var showingEdit = false

    private let today = Date()

    private var container: Container? { containers.first { $0.id == route.containerID } }
    private var nearDays: Int { stores.first?.nearExpiryDays ?? 2 }

    /// 首页提醒跳转过来时，要突出显示的格子
    private var focusCell: Int? {
        guard let id = route.focusItemID else { return nil }
        return container?.items.first { $0.id == id }?.cellIndex
    }

    /// 从格位弹窗里点「上架到此格」：先收起弹窗，再开上架表单
    /// （SwiftUI 不允许同一帧内连续切换两个 sheet，故错开一拍）
    private func openAddItem(in cell: Int) {
        selectedCell = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { addItemCell = cell }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if let container {
                    VStack(alignment: .leading, spacing: 14) {
                        summary(container)
                        cellGrid(container)
                    }
                    .padding(16)
                    .onAppear {
                        if let focusCell { proxy.scrollTo(focusCell, anchor: .center) }
                    }
                } else {
                    ContentUnavailableView("容器不存在",
                                           systemImage: "questionmark.square",
                                           description: Text("它可能已被删除"))
                }
            }
        }
        .background(Color.paper.ignoresSafeArea())
        .navigationTitle(container?.name ?? "容器")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: Binding(get: { selectedCell != nil },
                                    set: { if !$0 { selectedCell = nil } })) {
            if let cell = selectedCell, let container {
                CellSheet(container: container,
                          cellIndex: cell,
                          today: today,
                          nearDays: nearDays) { openAddItem(in: $0) }
            }
        }
        .toolbar {
            /// H7-2：`+` 是「改这个柜子」，不是上架。上架一律从点格子进
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingEdit = true } label: { Image(systemName: "slider.horizontal.3") }
            }
        }
        .sheet(isPresented: $showingEdit) {
            if let container { ContainerFormSheet(mode: .edit(container)) }
        }
        .sheet(isPresented: Binding(get: { addItemCell != nil },
                                    set: { if !$0 { addItemCell = nil } })) {
            if let container, let cell = addItemCell {
                AddItemSheet(container: container, preferredCell: cell)
            }
        }
    }

    private func summary(_ c: Container) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: c.type.symbolName).foregroundStyle(Color.brandGreen)
                Text("\(c.type.displayName) · 正视图 \(c.rows) × \(c.columns) · 每格纵深 \(c.depthCapacity)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            FillBar(ratio: c.fillRatio)
            Text("已用 \(c.usedCount) / 容量 \(c.totalCapacity) 件 · 共 \(c.cellCount) 格")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(.background, in: .rect(cornerRadius: 14))
    }

    /// 每行格子数严格等于 columns，行数由总数自然决定（验收标准 1）
    private func cellGrid(_ c: Container) -> some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: max(1, c.columns))
        return LazyVGrid(columns: columns, spacing: 10) {
            ForEach(0..<c.cellCount, id: \.self) { index in
                CellBox(container: c,
                        cellIndex: index,
                        today: today,
                        nearDays: nearDays,
                        focused: index == focusCell)
                    .id(index)
                    .onTapGesture { selectedCell = index }
            }
        }
    }
}

// MARK: - Subviews

/// 位置码徽章 —— H7 §1.3「位置码即视觉锚点」：
/// 同一个「黄底 B2」在首页提醒 / 格子内 / 下架列表三处长得完全一样，店长认一次就到处认得。
/// 配色沿用 DATABASE §4.3 状态表（黄底 = 临期，红底 = 过期），**比商品名更靠前、字号更大**
struct LocationBadge: View {
    enum Scale { case regular, large }

    let code: String
    let itemStatus: ItemStatus
    var scale: Scale = .regular

    private var large: Bool { scale == .large }

    var body: some View {
        Text(code)
            .font(.system(size: large ? 15 : 11, weight: .bold).monospacedDigit())
            .foregroundStyle(foreground)
            .padding(.horizontal, large ? 9 : 6)
            .padding(.vertical, large ? 5 : 3)
            .background(background, in: .capsule)
    }

    private var background: Color {
        switch itemStatus {
        case .normal: return .statusNormalBG
        case .near: return .statusNearBG
        case .expired: return .statusExpiredBG
        }
    }

    private var foreground: Color {
        switch itemStatus {
        case .normal: return .statusNormalFG
        case .near: return .statusNearFG
        case .expired: return .statusExpiredFG
        }
    }
}

/// 单个格子：标签 + 纵深小色块（沿用原型 `.cell` / `.unit` 视觉）
struct CellBox: View {
    let container: Container
    let cellIndex: Int
    let today: Date
    let nearDays: Int
    var focused: Bool = false

    private var cellItems: [Item] { items(in: container, cell: cellIndex) }

    private var label: String { excelColumnName(cellIndex) }
    private var emptySlots: Int { max(0, container.depthCapacity - cellItems.count) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(label).font(.system(size: 11, weight: .bold)).foregroundStyle(Color(hex: 0x66736B))
                Spacer(minLength: 0)
                Text("\(cellItems.count)/\(container.depthCapacity)")
                    .font(.system(size: 9))
                    .foregroundStyle(Color(hex: 0xA1AAA4))
            }

            if cellItems.isEmpty {
                Text("空格位").font(.system(size: 10)).foregroundStyle(Color(hex: 0xA1AAA4))
            } else {
                unitList
            }

            Spacer(minLength: 0)
        }
        .padding(11)
        .frame(minHeight: 120, alignment: .topLeading)
        .background(Color(hex: 0xFBFCFA), in: .rect(cornerRadius: 13))
        .overlay {
            RoundedRectangle(cornerRadius: 13)
                .stroke(strokeColor, lineWidth: strokeWidth)
        }
        .shadow(color: focused ? Color.brandGreen.opacity(0.25) : .clear, radius: 6, y: 2)
    }

    /// 已占用的显示位置码色块，未占用的显示虚线空位（PRD §5.3「未使用的容量保持空位显示」）
    ///
    /// 纵深表达（H7 §1.3）：越靠后越淡、越往右缩进一点 —— 一眼看出这一格的前后顺序
    private var unitList: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 30), spacing: 5)], spacing: 5) {
            ForEach(cellItems) { item in
                LocationBadge(code: item.locationCode,
                              itemStatus: unitColors(item).status)
                    .frame(minWidth: 34)
                    .opacity(1 - Double(min(3, item.depthIndex)) * 0.15)
                    .offset(x: CGFloat(min(3, item.depthIndex)) * 2)
            }
            ForEach(0..<emptySlots, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .foregroundStyle(Color(hex: 0xDDE4DC))
                    .frame(minWidth: 30, minHeight: 22)
            }
        }
    }

    /// 格内有临期 / 过期货时整格描边 —— 扫一眼柜子就知道哪一格要清
    private var attention: ItemStatus? {
        if cellItems.contains(where: { unitColors($0).status == .expired }) { return .expired }
        if cellItems.contains(where: { unitColors($0).status == .near }) { return .near }
        return nil
    }

    private var strokeColor: Color {
        if focused { return Color.brandGreen }
        switch attention {
        case .expired: return .statusExpiredBG
        case .near: return .statusNearBG
        default: return Color(hex: 0xE3E9E3)
        }
    }

    private var strokeWidth: CGFloat {
        focused ? 2 : (attention == nil ? 1 : 2)
    }

    /// 状态 + 配色沿用 DATABASE §4.3 的状态表（CR-5.3）
    private func unitColors(_ item: Item) -> (status: ItemStatus, background: Color, foreground: Color) {
        switch status(of: item, today: today, nearDays: nearDays) {
        case .normal: return (.normal, .statusNormalBG, .statusNormalFG)
        case .near: return (.near, .statusNearBG, .statusNearFG)
        case .expired: return (.expired, .statusExpiredBG, .statusExpiredFG)
        }
    }
}

/// 格位弹窗：列出该格内所有件（位置码、名称、条码后四位、日期、状态徽章）
struct CellSheet: View {
    let container: Container
    let cellIndex: Int
    let today: Date
    let nearDays: Int
    /// 直接把这一格作为目标打开上架表单（用户点格子就是想在这一格里操作）
    let onAddItem: (Int) -> Void

    @Environment(\.dismiss) private var dismiss

    private var cellItems: [Item] { items(in: container, cell: cellIndex) }

    var body: some View {
        NavigationStack {
            Group {
                if cellItems.isEmpty {
                    ContentUnavailableView("格子 \(excelColumnName(cellIndex)) 是空的",
                                           systemImage: "square.dashed",
                                           description: Text("可存放 \(container.depthCapacity) 件，上架后自动占第一个空位"))
                } else {
                    List(cellItems) { item in
                        HStack(spacing: 12) {
                            LocationBadge(code: item.locationCode,
                                          itemStatus: status(of: item, today: today, nearDays: nearDays),
                                          scale: .large)
                                .frame(width: 46, alignment: .leading)
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Text(item.displayName).font(.subheadline.weight(.semibold))
                                    Text("·\(item.barcodeSuffix4)")
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                                Text("过期 \(item.expiryDate.formatted(date: .numeric, time: .omitted))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            StatusBadge(status: status(of: item, today: today, nearDays: nearDays))
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .navigationTitle("格子 \(excelColumnName(cellIndex))")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                Button { onAddItem(cellIndex) } label: {
                    Label("上架到 \(excelColumnName(cellIndex)) 格", systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.brandGreen)
                .padding(16)
                .background(.bar)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Previews

#Preview("容器列表") {
    ContainerListView()
        .modelContainer(PreviewSample.container)
}

#Preview("容器详情 · 高亮 B2") {
    let items = try! ModelContext(PreviewSample.container).fetch(FetchDescriptor<Item>())
    let target = items.first { $0.locationCode == "B2" } ?? items[0]
    NavigationStack {
        ContainerDetailView(route: ContainerRoute(containerID: target.container!.id,
                                                  focusItemID: target.id))
    }
    .modelContainer(PreviewSample.container)
}
