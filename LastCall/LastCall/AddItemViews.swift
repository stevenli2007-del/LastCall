//
//  AddItemViews.swift
//  LastCall
//
//  上架流程：条码（扫码或手输）→ 生产日期 → 保质天数 → 过期预览 → 写入 nextSlot。
//  保质天数默认继承上一件商品，修改只影响当前与后续默认值，绝不回写历史商品（PRD §5.3 / 验收标准 2）。
//  条码全程 String，前导零不丢（验收标准 8）。
//

import SwiftUI
import SwiftData

// MARK: - Views

struct AddItemSheet: View {
    let container: Container
    /// 首选格子；该格满时由 nextSlot 自动顺延到下一个有空位的格子
    let preferredCell: Int

    @Query(sort: \Item.createdAt, order: .reverse) private var recentItems: [Item]
    @Query private var stores: [Store]
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var selectedCell = 0
    @State private var barcode = ""
    @State private var name = ""
    @State private var productionDate = Date()
    @State private var shelfLifeDays = 10
    @State private var showingScanner = false
    @State private var savedLocation: String?
    @State private var errorMessage: String?
    @State private var didLoadDefaultShelfLife = false
    @State private var refreshTick = 0

    private let today = Date()

    // MARK: Helpers

    private var nearDays: Int { stores.first?.nearExpiryDays ?? 2 }
    private var trimmedBarcode: String { barcode.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// 位置由用户选的格子决定；该格满时 nextSlot 顺延到下一个有空位的格子
    /// 读一次 refreshTick：保存后强制本视图重算，避免预览停在旧位置
    private var slot: (cell: Int, depth: Int)? {
        _ = refreshTick
        return nextSlot(in: container, preferredCell: selectedCell)
    }

    /// 所选格子当前已占用的件数，给预览核对用
    private var selectedCellUsed: Int {
        container.items.filter { $0.cellIndex == selectedCell }.count
    }

    /// 格子选择器的标签：A · 2/5；已满的标「满」
    private func cellPickerLabel(_ cell: Int) -> String {
        let used = container.items.filter { $0.cellIndex == cell }.count
        let name = excelColumnName(cell)
        return used >= container.depthCapacity ? "\(name) · \(tr("满", "Full"))" : "\(name) · \(used)/\(container.depthCapacity)"
    }

    private var expiryDate: Date { Calendar.current.dateByAddingDays(shelfLifeDays, to: productionDate) }

    private var previewStatus: ItemStatus {
        status(ofExpiry: expiryDate, today: today, nearDays: nearDays)
    }

    private var locationPreview: String {
        guard let slot else { return tr("无可用位置", "No space") }
        return "\(container.name) \(excelColumnName(slot.cell))\(slot.depth + 1)"
    }

    // MARK: Body

    var body: some View {
        NavigationStack {
            Form {
                cellSection
                barcodeSection
                infoSection
                previewSection
                feedbackSection
            }
            .navigationTitle(tr("上架 · \(container.name)", "Add · \(container.name)"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(tr("取消", "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(tr("保存", "Save")) { save() }
                        .disabled(trimmedBarcode.isEmpty || slot == nil)
                }
            }
            .sheet(isPresented: $showingScanner) {
                ScannerSheet(title: "扫描商品条码") { code in barcode = code }
            }
            .onAppear(perform: loadDefaultShelfLife)
        }
    }

    // MARK: Subviews

    /// 选目标格子（PRD §5.3：选择格子后按纵深顺序录入，纵深不能自选 —— 不变量 I2 要求格内连续无空洞）
    private var cellSection: some View {
        Section(tr("目标格子", "Target Cell")) {
            Picker(tr("格子", "Cell"), selection: $selectedCell) {
                ForEach(0..<container.cellCount, id: \.self) { cell in
                    Text(cellPickerLabel(cell)).tag(cell)
                }
            }

            if let slot, slot.cell != selectedCell {
                Text(tr("\(excelColumnName(selectedCell)) 已满，将自动顺延到有空位的 \(excelColumnName(slot.cell)) 格",
                        "\(excelColumnName(selectedCell)) is full — will use next free cell \(excelColumnName(slot.cell))"))
                    .font(.caption)
                    .foregroundStyle(Color.statusNearFG)
            }
        }
    }

    private var barcodeSection: some View {
        Section(tr("条码", "Barcode")) {
            HStack(spacing: 10) {
                TextField(tr("扫码或手动输入", "Scan or enter manually"), text: $barcode)
                    .keyboardType(.numberPad)
                    .font(.body.monospacedDigit())
                Button {
                    showingScanner = true
                } label: {
                    Image(systemName: "barcode.viewfinder").font(.title3)
                }
                .buttonStyle(.bordered)
                .tint(Color.brandGreen)
            }

            if !trimmedBarcode.isEmpty {
                Text(tr("末四位 \(barcodeSuffix(of: trimmedBarcode)) · 下架时按完整条码比对",
                        "Last 4: \(barcodeSuffix(of: trimmedBarcode)) · full barcode required at removal"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var infoSection: some View {
        Section(tr("商品信息", "Item Info")) {
            TextField(tr("商品名称（选填）", "Name (optional)"), text: $name)
            DatePicker(tr("生产日期", "Production Date"),
                       selection: $productionDate,
                       in: ...Date.now,
                       displayedComponents: .date)
            Stepper(tr("保质期 \(shelfLifeDays) 天", "Shelf life \(shelfLifeDays)d"), value: $shelfLifeDays, in: 1...365)
            Text(tr("默认值继承上一件商品；修改只影响当前这一件与后续默认值，不会回写已录入的商品",
                    "Default inherits the last item; changes affect only this item and future defaults"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var previewSection: some View {
        Section(tr("上架预览", "Preview")) {
            if slot == nil {
                Text("容器已装满，没有空位")
                    .foregroundStyle(Color.statusExpiredFG)
            } else {
                LabeledContent(tr("生产日期", "Production"), value: productionDate.formatted(date: .numeric, time: .omitted))
                LabeledContent(tr("过期日期", "Expiry"), value: expiryDate.formatted(date: .numeric, time: .omitted))
                HStack {
                    Text(tr("届时状态", "Status then"))
                    Spacer(minLength: 0)
                    StatusBadge(status: previewStatus)
                }
                LabeledContent(tr("存入位置", "Location"), value: locationPreview)
                LabeledContent(tr("该格现有", "Cell usage"), value: "\(selectedCellUsed)/\(container.depthCapacity)")
                Text(tr("过期日期 = 生产日期 + 保质期，生产当天算第 0 天",
                        "Expiry = production date + shelf life; production day counts as day 0"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(tr("位置 = 所选格子的下一个空位，纵深按顺序自动排（格内不能留空洞）",
                        "Location = next free slot in the chosen cell; depth auto-assigned in order"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var feedbackSection: some View {
        if let savedLocation {
            Section {
                Label(tr("已存入 \(container.name) \(savedLocation)，可继续录下一件",
                         "Saved to \(container.name) \(savedLocation) — ready for the next one"),
                      systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Color.brandGreen)
                    .font(.footnote)
            }
        }
        if let errorMessage {
            Section {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(Color.statusExpiredFG)
            }
        }
    }

    // MARK: Actions

    /// 首次打开：选中外部传入的默认格子（高亮格或第一个未满格）；
    /// 保质天数默认值 = 最近录入那一件的值，没有历史数据则用 10
    private func loadDefaultShelfLife() {
        guard !didLoadDefaultShelfLife else { return }
        didLoadDefaultShelfLife = true
        selectedCell = preferredCell
        shelfLifeDays = recentItems.first?.shelfLifeDays ?? 10
    }

    /// 保存后不清空格子、保质天数与生产日期 —— 同一批次连续录入时少改三次
    private func save() {
        do {
            let item = try addItem(barcode: trimmedBarcode,
                                   name: trimmedName,
                                   productionDate: productionDate,
                                   shelfLifeDays: shelfLifeDays,
                                   to: container,
                                   preferredCell: selectedCell,
                                   context: context)
            savedLocation = item.locationCode
            errorMessage = nil
            barcode = ""
            name = ""
            refreshTick += 1          // 强制重算 slot，预览立刻显示下一个空位
        } catch {
            savedLocation = nil
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Previews

#Preview("上架 · 牛奶冰柜") {
    let sample = PreviewSample.container
    let context = ModelContext(sample)
    let containers = try! context.fetch(FetchDescriptor<Container>())
    let fridge = containers.first { $0.name == "牛奶冰柜" } ?? containers[0]
    return AddItemSheet(container: fridge, preferredCell: 0)
        .modelContainer(sample)
}
