//
//  ScanViews.swift
//  LastCall
//
//  VisionKit 扫码封装 + 扫码 sheet。上架（H3）与下架核验（H4）共用。
//  相机不可用 / 权限被拒时必须能手动输入完成流程（CR-5.6）。
//  全部识别在设备端完成，不联网（CR-3.3）。
//

import SwiftUI
import SwiftData
import VisionKit
import Vision          // VNBarcodeSymbology 在 Vision 框架里

// MARK: - VisionKit 封装

/// 条码扫描器。识别到第一个条码即回调并停止扫描
struct BarcodeScanner: UIViewControllerRepresentable {
    let onFound: (String) -> Void
    let onUnavailable: (String) -> Void

    /// 国内商品常见的一维码；二维码不在范围内
    private static let symbologies: [VNBarcodeSymbology] = [.ean13, .ean8, .upce, .code128, .code93, .code39]

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: Self.symbologies)],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {
        guard !context.coordinator.didStart else { return }
        context.coordinator.didStart = true
        do {
            try controller.startScanning()
        } catch {
            onUnavailable("无法启动相机：\(error.localizedDescription)")
        }
    }

    static func dismantleUIViewController(_ controller: DataScannerViewController,
                                          coordinator: Coordinator) {
        controller.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let parent: BarcodeScanner
        var didStart = false
        private var found = false

        init(parent: BarcodeScanner) { self.parent = parent }

        func dataScanner(_ dataScanner: DataScannerViewController,
                         didAdd addedItems: [RecognizedItem],
                         allItems: [RecognizedItem]) {
            guard let payload = firstPayload(in: addedItems) else { return }
            report(payload, from: dataScanner)
        }

        func dataScanner(_ dataScanner: DataScannerViewController,
                         didTapOn item: RecognizedItem) {
            guard let payload = firstPayload(in: [item]) else { return }
            report(payload, from: dataScanner)
        }

        func dataScanner(_ dataScanner: DataScannerViewController,
                         becameUnavailableWithError error: Error) {
            parent.onUnavailable(error.localizedDescription)
        }

        /// 只认第一个有效条码，找到后立刻停扫，避免连续重复回调
        private func report(_ payload: String, from dataScanner: DataScannerViewController) {
            guard !found else { return }
            found = true
            dataScanner.stopScanning()
            parent.onFound(payload)
        }

        private func firstPayload(in items: [RecognizedItem]) -> String? {
            for item in items {
                if case .barcode(let barcode) = item,
                   let payload = barcode.payloadStringValue,
                   !payload.isEmpty {
                    return payload
                }
            }
            return nil
        }
    }
}

// MARK: - Views

/// 扫码 sheet。相机不可用时自动退化成纯手输界面，流程不中断
struct ScannerSheet: View {
    let title: String
    let onFound: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var manualCode = ""
    @State private var notice: String?
    @State private var cameraUnavailable = false

    private var canScan: Bool {
        !cameraUnavailable && DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    var body: some View {
        NavigationStack {
            ZStack {
                if canScan {
                    BarcodeScanner(
                        onFound: { code in
                            onFound(code)
                            dismiss()
                        },
                        onUnavailable: { message in
                            cameraUnavailable = true
                            notice = message
                        }
                    )
                    .ignoresSafeArea()
                } else {
                    fallbackArea
                }
            }
            .safeAreaInset(edge: .bottom) { manualBar }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }

    // MARK: Subviews

    private var fallbackArea: some View {
        VStack(spacing: 12) {
            Image(systemName: "camera.slash")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(cameraUnavailable ? "相机不可用" : "此设备不支持扫码")
                .font(.headline)
            if let notice {
                Text(notice).font(.footnote).foregroundStyle(.secondary)
            }
            Text("可直接在下方手动输入条码，流程不受影响")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.paper.ignoresSafeArea())
    }

    private var manualBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "barcode")
                    .foregroundStyle(Color.brandGreen)
                TextField("手动输入完整条码", text: $manualCode)
                    .keyboardType(.numberPad)
                    .textInputAutocapitalization(.never)
                    .font(.body.monospacedDigit())
            }
            .padding(12)
            .background(.background, in: .rect(cornerRadius: 12))

            Button {
                let code = manualCode.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !code.isEmpty else { return }
                onFound(code)
                dismiss()
            } label: {
                Text("使用该条码")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.brandGreen)
            .disabled(manualCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(16)
        .background(.bar)
    }
}

// MARK: - 下架流程

/// 下架列表：按过期日期升序（最快过期的在前）。选中单件后进入扫码核验
struct RemoveListView: View {
    @Query private var items: [Item]
    @Query private var stores: [Store]
    @State private var selected: Item?

    private let today = Date()
    private var nearDays: Int { stores.first?.nearExpiryDays ?? 2 }
    private var sorted: [Item] { items.sorted { $0.expiryDate < $1.expiryDate } }

    var body: some View {
        NavigationStack {
            Group {
                if sorted.isEmpty {
                    ContentUnavailableView("库存为空",
                                           systemImage: "shippingbox",
                                           description: Text("上架商品后即可在这里下架"))
                } else {
                    List(sorted) { item in
                        Button { selected = item } label: {
                            AlertRow(item: item, today: today, nearDays: nearDays)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .background(Color.paper.ignoresSafeArea())
            .navigationTitle("下架")
            .sheet(item: $selected) { item in
                RemoveConfirmSheet(item: item, today: today, nearDays: nearDays)
            }
        }
    }
}

/// 下架核验：选中单件 → 扫完整条码 → 精确比对 → 同事务「留档 + 删除 + 同格前移」（PRD §5.4）
/// 条码不匹配时**不修改任何库存**（验收标准 5）
struct RemoveConfirmSheet: View {
    let item: Item
    let today: Date
    let nearDays: Int

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var scanned: String?
    @State private var message: String?
    @State private var showingScanner = false
    @State private var removedName: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                if let removedName {
                    removedView(removedName)
                } else {
                    infoCard
                    statusArea
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .background(Color.paper.ignoresSafeArea())
            .navigationTitle(removedName == nil ? "下架核验" : "已下架")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
            .sheet(isPresented: $showingScanner) {
                ScannerSheet(title: "核验商品条码") { code in scanned = code }
            }
        }
    }

    // MARK: Subviews

    private var infoCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(item.displayName).font(.headline)
                Text("·\(item.barcodeSuffix4)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Text("\(item.container?.name ?? "未知容器") \(item.locationCode)")
                .font(.subheadline)
                .foregroundStyle(Color.brandGreen)
            Text("过期 \(item.expiryDate.formatted(date: .numeric, time: .omitted))")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.background, in: .rect(cornerRadius: 14))
    }

    @ViewBuilder
    private var statusArea: some View {
        if let code = scanned {
            if code == item.barcode {
                Label("条码匹配，可安全下架", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Color.brandGreen)
                Button(role: .destructive) {
                    performRemove()
                } label: {
                    Text("确认下架").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            } else {
                Label("条码不匹配（扫到 \(code)），库存未做任何修改",
                      systemImage: "xmark.octagon.fill")
                    .foregroundStyle(Color.statusExpiredFG)
                    .font(.footnote)
                scanButton("重新扫描")
            }
        } else {
            Text("扫描该商品的完整条码，确认拿取的是这一件")
                .font(.footnote)
                .foregroundStyle(.secondary)
            scanButton("扫描条码核验")
        }

        if let message {
            Text(message).font(.footnote).foregroundStyle(Color.statusExpiredFG)
        }
    }

    private func scanButton(_ title: String) -> some View {
        Button { showingScanner = true } label: {
            Label(title, systemImage: "barcode.viewfinder")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(Color.brandGreen)
    }

    private func removedView(_ name: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.largeTitle)
                .foregroundStyle(Color.brandGreen)
            Text("\(name) 已下架")
                .font(.headline)
            Text("已留档，同格后方商品自动前移补位")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    // MARK: Actions

    /// 先取出名字再删除：删除后不能再访问 item 的任何属性
    private func performRemove() {
        guard let code = scanned else { return }
        let name = item.displayName
        do {
            try remove(item: item, scannedBarcode: code, context: context)
            removedName = name
        } catch {
            message = error.localizedDescription
        }
    }
}

// MARK: - Previews

/// 预览不启动相机（模拟器与 Canvas 均不支持 DataScanner），只验证手输兜底路径
#Preview("扫码 · 相机不可用") {
    ScannerSheet(title: "扫描条码") { code in
        print("扫到：\(code)")
    }
}
