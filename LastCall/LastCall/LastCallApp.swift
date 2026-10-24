//
//  LastCallApp.swift
//  LastCall
//
//  App 入口：ModelContainer 配置 + 首次启动 seed。
//  不含任何业务代码（见 CODINGRULES §1）。
//

import SwiftUI
import SwiftData

@main
struct LastCallApp: App {
    private static let schema = Schema([
        Store.self,
        Container.self,
        Item.self,
        RemovalRecord.self
    ])

    private let modelContainer: ModelContainer

    init() {
        do {
            modelContainer = try ModelContainer(
                for: Self.schema,
                configurations: ModelConfiguration(schema: Self.schema, isStoredInMemoryOnly: false)
            )
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
        seedIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(modelContainer)
    }

    // MARK: - Helpers

    /// 首次启动写入默认门店与演示容器；已有数据则原样不动
    private func seedIfNeeded() {
        let context = ModelContext(modelContainer)
        let existing = (try? context.fetchCount(FetchDescriptor<Store>())) ?? 0
        guard existing == 0 else { return }

        let store = SeedData.makeDefaultStore()
        context.insert(store)
        for container in SeedData.makeDemoContainers() {
            container.store = store
            store.containers.append(container)
            context.insert(container)
        }
        try? context.save()
    }
}
