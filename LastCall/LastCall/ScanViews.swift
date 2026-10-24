//
//  ScanViews.swift
//  LastCall
//
//  VisionKit 扫码封装 + 扫码 sheet。上架（H3）与下架核验（H4）共用。
//  相机不可用 / 权限被拒时必须能手动输入完成流程（CR-5.6）。
//  全部识别在设备端完成，不联网（CR-3.3）。
//

import SwiftUI
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

// MARK: - Previews

/// 预览不启动相机（模拟器与 Canvas 均不支持 DataScanner），只验证手输兜底路径
#Preview("扫码 · 相机不可用") {
    ScannerSheet(title: "扫描条码") { code in
        print("扫到：\(code)")
    }
}
