import Foundation

/// 所有文件路径集中管理
/// - Application Support：数据库、内部 GPS 轨迹（「文件」App 看不到）
/// - Documents：GPX/CSV 导出、备份（开启了文件共享，「文件」App → 我的 iPhone → 行车记录 可见）
enum AppPaths {
    static var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static var applicationSupport: URL {
        ensure(FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0])
    }

    static var storeURL: URL {
        applicationSupport.appendingPathComponent("DriveLog.store")
    }

    static var tracksDirectory: URL {
        ensure(applicationSupport.appendingPathComponent("Tracks", isDirectory: true))
    }

    static var activeTripStateURL: URL {
        applicationSupport.appendingPathComponent("active_trip.json")
    }

    static var tripExportsDirectory: URL {
        ensure(documents.appendingPathComponent("行程轨迹", isDirectory: true))
    }

    static var dataExportsDirectory: URL {
        ensure(documents.appendingPathComponent("数据导出", isDirectory: true))
    }

    static var backupsDirectory: URL {
        ensure(documents.appendingPathComponent("备份", isDirectory: true))
    }

    static var temporaryDirectory: URL {
        ensure(FileManager.default.temporaryDirectory.appendingPathComponent("DriveLogTmp", isDirectory: true))
    }

    @discardableResult
    static func ensure(_ url: URL) -> URL {
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) {
            try? fm.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return url
    }
}
