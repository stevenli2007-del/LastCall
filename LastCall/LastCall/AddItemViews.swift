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

    @State private var barcode = ""
    @State private var name = ""
    @State private var productionDate = Date()
    @State private var shelfLifeDays = 10
    @State private var showingScanner = false
    @State private var savedLocation: String?
    @State private var errorMessage: String?
    @State private var didLoadDefaultShelfLife = false

    private let today = Date()

    // MARK: Helpers

    private var nearDays: Int { stores.first?.nearExpiryDays ?? 2 }
    private var trimmedBarcode: String { barcode.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var slot: (cell: Int, depth: Int)? { nextSlot(in: container, preferredCell: preferredCell) }

    private var expiryDate: Date { Calendar.current.dateByAddingDays(shelfLifeDays, to: productionDate) }

    private var previewStatus: ItemStatus {
        status(ofExpiry: expiryDate, today: today, nearDays: nearDays)
    }

    private var locationPreview: String {
        guard let slot else { return "无可用位置" }
        return "\(container.name) \(excelColumnName(slot.cell))\(slot.depth + 1)"
    }

    // MARK: Body

    var body: some View {
        NavigationStack {
            Form {
                barcodeSection
                infoSection
                previewSection
                feedbackSection
            }
            .navigationTitle("上架 · \(container.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") { save() }
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

    private var barcodeSection: some View {
        Section("条码") {
            HStack(spacing: 10) {
                TextField("扫码或手动输入", text: $barcode)
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
                Text("末四位 \(barcodeSuffix(of: trimmedBarcode)) · 下架时按完整条码比对")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var infoSection: some View {
        Section("商品信息") {
            TextField("商品名称（选填）", text: $name)
            DatePicker("生产日期",
                       selection: $productionDate,
                       in: ...Date.now,
                       displayedComponents: .date)
            Stepper("预计存储 \(shelfLifeDays) 天", value: $shelfLifeDays, in: 1...365)
            Text("默认值继承上一件商品；修改只影响当前这一件与后续默认值，不会回写已录入的商品")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var previewSection: some View {
        Section("上架预览") {
            if slot == nil {
                Text("容器已装满，没有空位")
                    .foregroundStyle(Color.statusExpiredFG)
            } else {
                LabeledContent("生产日期", value: productionDate.formatted(date: .numeric, time: .omitted))
                LabeledContent("过期日期", value: expiryDate.formatted(date: .numeric, time: .omitted))
                HStack {
                    Text("届时状态")
                    Spacer(minLength: 0)
                    StatusBadge(status: previewStatus)
                }
                LabeledContent("存入位置", value: locationPreview)
                Text("过期日期 = 生产日期 + 预计存储天数，生产当天算第 0 天")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var feedbackSection: some View {
        if let savedLocation {
            Section {
                Label("已存入 \(container.name) \(savedLocation)，可继续录下一件",
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

    /// 保质天数默认值 = 最近录入那一件的值；没有历史数据则用 10
    private func loadDefaultShelfLife() {
        guard !didLoadDefaultShelfLife else { return }
        didLoadDefaultShelfLife = true
        shelfLifeDays = recentItems.first?.shelfLifeDays ?? 10
    }

    /// 保存后不清空保质天数与生产日期 —— 同批次连续录入时少改两次
    private func save() {
        do {
            let item = try addItem(barcode: trimmedBarcode,
                                   name: trimmedName,
                                   productionDate: productionDate,
                                   shelfLifeDays: shelfLifeDays,
                                   to: container,
                                   preferredCell: preferredCell,
                                   context: context)
            savedLocation = item.locationCode
            errorMessage = nil
            barcode = ""
            name = ""
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
