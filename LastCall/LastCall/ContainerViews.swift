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
            .sheet(isPresented: $showingCreate) { CreateContainerSheet() }
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

    private let today = Date()

    private var container: Container? { containers.first { $0.id == route.containerID } }
    private var nearDays: Int { stores.first?.nearExpiryDays ?? 2 }

    /// 首页提醒跳转过来时，要突出显示的格子
    private var focusCell: Int? {
        guard let id = route.focusItemID else { return nil }
        return container?.items.first { $0.id == id }?.cellIndex
    }

    /// 上架默认落在高亮格；没有高亮时落在第一个还有空位的格子
    private var defaultAddCell: Int {
        guard let container else { return 0 }
        if let focusCell { return focusCell }
        return (0..<container.cellCount).first { nextDepth(in: container, cell: $0) != nil } ?? 0
    }

    /// 从格位弹窗里点「上架到此格」：先收起弹窗，再开上架表单
    /// （SwiftUI 不允许同一帧内连续切换两个 sheet，故错开一拍）
    private func openAddItem(in cell: Int) {
        selectedCell = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { addItemCell = cell }
    }

    var body: some View {
        ScrollView {
            if let container {
                VStack(alignment: .leading, spacing: 14) {
                    summary(container)
                    cellGrid(container)
                }
                .padding(16)
            } else {
                ContentUnavailableView("容器不存在",
                                       systemImage: "questionmark.square",
                                       description: Text("它可能已被删除"))
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
            ToolbarItem(placement: .topBarTrailing) {
                Button { addItemCell = defaultAddCell } label: { Image(systemName: "plus") }
            }
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

    /// 柜体正视图：整柜渲染，格位按 rows × columns 真实排布（验收标准 1 / H7 第 1 项）
    private func cellGrid(_ c: Container) -> some View {
        ShelfView(container: c,
                  today: today,
                  nearDays: nearDays,
                  focusCell: focusCell) { selectedCell = $0 }
    }
}

// MARK: - Subviews

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
                                          status: status(of: item, today: today, nearDays: nearDays),
                                          prominent: true)
                                .frame(width: 44, alignment: .leading)
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

/// 新建容器：名称 / 类型 / rows × cols × depthCapacity，默认 3 × 2 × 5（PRD §5.3）
struct CreateContainerSheet: View {
    @Query private var stores: [Store]
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var type: ContainerType = .fridge
    @State private var rows = 3
    @State private var columns = 2
    @State private var depth = 5

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                Section("基本信息") {
                    TextField("容器名称", text: $name)
                    Picker("类型", selection: $type) {
                        ForEach(ContainerType.allCases) { t in
                            Text(t.displayName).tag(t)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("正视图与纵深") {
                    Stepper("行数 \(rows)", value: $rows, in: 1...8)
                    Stepper("列数 \(columns)", value: $columns, in: 1...8)
                    Stepper("每格纵深 \(depth) 件", value: $depth, in: 1...10)
                    Text("正视图 \(rows) × \(columns) = \(rows * columns) 格（\(excelColumnName(0))–\(excelColumnName(rows * columns - 1))），总容量 \(rows * columns * depth) 件")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("新建容器")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") { save() }
                        .disabled(trimmedName.isEmpty)
                }
            }
        }
    }

    private func save() {
        let container = Container(name: trimmedName,
                                  type: type,
                                  rows: rows,
                                  columns: columns,
                                  depthCapacity: depth)
        context.insert(container)
        if let store = stores.first {
            container.store = store
            store.containers.append(container)
        }
        try? context.save()
        dismiss()
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
