import Foundation
import SwiftData

/// 全局唯一的 SwiftData 容器。App Intent 在后台启动时也会用到它，
/// 所以不依赖任何视图，第一次访问时创建。
@MainActor
final class DataStore {
    static let shared = DataStore()

    static let schema = Schema([
        Vehicle.self,
        Trip.self,
        FuelEntry.self,
        Expense.self,
        ExpenseCategory.self,
        MaintenanceReminder.self
    ])

    let container: ModelContainer
    /// 如果数据库打不开（极少见），旧文件会被改名保留，这里记录原因用于提示
    private(set) var recoveryMessage: String?

    var context: ModelContext { container.mainContext }

    private init() {
        let url = AppPaths.storeURL
        do {
            container = try DataStore.makeContainer(url: url)
        } catch {
            let stamp = Int(Date().timeIntervalSince1970)
            for suffix in ["", "-wal", "-shm"] {
                let src = URL(fileURLWithPath: url.path + suffix)
                let dst = URL(fileURLWithPath: url.path + suffix + ".broken-\(stamp)")
                try? FileManager.default.moveItem(at: src, to: dst)
            }
            recoveryMessage = "数据库无法打开（\(error.localizedDescription)），旧文件已改名保留。可以从备份恢复数据。"
            do {
                container = try DataStore.makeContainer(url: url)
            } catch {
                fatalError("无法创建数据库：\(error)")
            }
        }
    }

    private static func makeContainer(url: URL) throws -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema, url: url, allowsSave: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    func save() {
        do {
            try context.save()
        } catch {
            print("SwiftData 保存失败：\(error)")
        }
    }
}
