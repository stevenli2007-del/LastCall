//
//  ContainerFormView.swift
//  LastCall
//
//  容器的新建 / 编辑表单（H7-2）。
//  右上角 `+` 走编辑态：改名称、类型、行数 × 列数 × 每格纵深。
//  缩小会让已有商品悬空时**拒绝保存**，红字列出冲突格（不变量 I1 / I2，不做自动搬家）。
//
//  ⑦ 号文件槽位原登记给 ContainerShelfView（柜体正视图，H7-1 已回滚暂缓），
//  本轮重用于容器表单；柜体改造恢复时再申请新槽位。见 TECHSTACK ADR-006。
//

import SwiftUI
import SwiftData

// MARK: - ContainerFormSheet

struct ContainerFormSheet: View {
    enum Mode {
        case create
        case edit(Container)
    }

    let mode: Mode

    @Query private var stores: [Store]
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var type: ContainerType
    @State private var rows: Int
    @State private var columns: Int
    @State private var depth: Int

    init(mode: Mode) {
        self.mode = mode
        if case .edit(let c) = mode {
            _name = State(initialValue: c.name)
            _type = State(initialValue: c.type)
            _rows = State(initialValue: c.rows)
            _columns = State(initialValue: c.columns)
            _depth = State(initialValue: c.depthCapacity)
        } else {
            _name = State(initialValue: "")
            _type = State(initialValue: .fridge)
            _rows = State(initialValue: 3)
            _columns = State(initialValue: 2)
            _depth = State(initialValue: 5)
        }
    }

    private var editing: Container? {
        if case .edit(let c) = mode { return c }
        return nil
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var newCellCount: Int { rows * columns }

    /// 缩小后哪些商品会悬空。返回空 = 可以安全保存
    private var conflicts: [ResizeConflict] {
        guard let c = editing else { return [] }
        return resizeConflicts(in: c, rows: rows, columns: columns, depthCapacity: depth)
    }

    var body: some View {
        NavigationStack {
            Form {
                basicSection
                sizeSection
                if !conflicts.isEmpty { conflictSection }
            }
            .navigationTitle(editing == nil ? "新建容器" : "编辑容器")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") { save() }
                        .disabled(trimmedName.isEmpty || !conflicts.isEmpty)
                }
            }
        }
    }

    // MARK: Sections

    private var basicSection: some View {
        Section("基本信息") {
            TextField("容器名称", text: $name)
            Picker("类型", selection: $type) {
                ForEach(ContainerType.allCases) { t in
                    Text(t.displayName).tag(t)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    @ViewBuilder
    private var sizeSection: some View {
        Section {
            Stepper("行数 \(rows)", value: $rows, in: 1...8)
            Stepper("列数 \(columns)", value: $columns, in: 1...8)
            Stepper("每格纵深 \(depth) 件", value: $depth, in: 1...10)

            Text("正视图 \(rows) × \(columns) = \(newCellCount) 格"
                 + "（\(excelColumnName(0))–\(excelColumnName(newCellCount - 1))），"
                 + "总容量 \(newCellCount * depth) 件")
                .font(.footnote)
                .foregroundStyle(.secondary)

            if let c = editing {
                Text("当前 \(c.rows) × \(c.columns) × \(c.depthCapacity)"
                     + "（\(c.cellCount) 格 / 容量 \(c.totalCapacity) 件 / 在库 \(c.usedCount) 件）")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("正视图与纵深")
        } footer: {
            Text("变大随时可以；变小只有在所有商品都还装得下时才允许。")
        }
    }

    private var conflictSection: some View {
        Section {
            ForEach(conflicts) { c in
                Label(c.message, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
            Text("请先把这些商品下架或移到别的格子，再来改规格。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } header: {
            Text("无法缩小")
        }
    }

    // MARK: Actions

    private func save() {
        if let container = editing {
            container.name = trimmedName
            container.type = type
            container.rows = max(1, rows)
            container.columns = max(1, columns)
            container.depthCapacity = max(1, depth)
        } else {
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
        }
        try? context.save()
        dismiss()
    }
}

// MARK: - Previews

#Preview("编辑 · 牛奶冰柜") {
    let ctx = ModelContext(PreviewSample.container)
    let fridge = try! ctx.fetch(FetchDescriptor<Container>()).first { $0.name == "牛奶冰柜" }!
    return ContainerFormSheet(mode: .edit(fridge))
        .modelContainer(PreviewSample.container)
}

#Preview("新建") {
    ContainerFormSheet(mode: .create)
        .modelContainer(PreviewSample.container)
}
