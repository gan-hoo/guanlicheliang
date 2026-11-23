import Foundation

/// 内部轨迹文件：Application Support/Tracks/<tripID>.csv
enum TrackStore {
    static func url(for id: UUID) -> URL {
        AppPaths.tracksDirectory.appendingPathComponent("\(id.uuidString).csv")
    }

    static func exists(_ id: UUID) -> Bool {
        FileManager.default.fileExists(atPath: url(for: id).path)
    }

    static func createEmpty(for id: UUID) throws {
        let fileURL = url(for: id)
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            guard FileManager.default.createFile(atPath: fileURL.path, contents: Data()) else {
                throw CocoaError(.fileWriteUnknown)
            }
        }
    }

    static func readPoints(for id: UUID) -> [TrackPoint] {
        readPoints(from: url(for: id))
    }

    static func readPoints(from fileURL: URL) -> [TrackPoint] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return parse(String(decoding: data, as: UTF8.self))
    }

    static func parse(_ text: String) -> [TrackPoint] {
        var result: [TrackPoint] = []
        for line in text.split(separator: "\n") {
            if let point = TrackPoint(csvLine: line) {
                result.append(point)
            }
        }
        return result
    }

    /// 用给定的点整体覆盖轨迹文件
    static func overwrite(_ id: UUID, points: [TrackPoint]) {
        let text = points.map(\.csvLine).joined()
        try? Data(text.utf8).write(to: url(for: id), options: .atomic)
    }

    static func delete(_ id: UUID) {
        try? FileManager.default.removeItem(at: url(for: id))
    }

    /// 所有内部轨迹文件对应的行程 ID
    static func allTrackIDs() -> [UUID] {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: AppPaths.tracksDirectory.path)) ?? []
        return files.compactMap { name in
            guard name.hasSuffix(".csv") else { return nil }
            return UUID(uuidString: String(name.dropLast(4)))
        }
    }
}

/// 边记边追加写入磁盘：内存里只缓冲几秒，定时 flush + fsync
final class TrackWriter {
    let fileURL: URL
    private var handle: FileHandle?
    private var buffer = ""
    private var lastFlush = Date()
    private let flushInterval: TimeInterval

    init(fileURL: URL, flushInterval: TimeInterval = 4) throws {
        self.fileURL = fileURL
        self.flushInterval = flushInterval
        let fm = FileManager.default
        if !fm.fileExists(atPath: fileURL.path) {
            fm.createFile(atPath: fileURL.path, contents: Data())
        }
        let h = try FileHandle(forUpdating: fileURL)
        let end = try h.seekToEnd()
        if end > 0 {
            // 上次可能在写一半时被杀：如果最后不是换行，先补一个换行，避免两行粘在一起
            try h.seek(toOffset: end - 1)
            let lastByte = try h.read(upToCount: 1)
            try h.seekToEnd()
            if let lastByte, lastByte != Data([0x0A]) {
                try h.write(contentsOf: Data([0x0A]))
            }
        }
        handle = h
    }

    deinit {
        try? handle?.close()
    }

    func append(_ point: TrackPoint) {
        buffer += point.csvLine
        if Date().timeIntervalSince(lastFlush) >= flushInterval {
            flush()
        }
    }

    func flush() {
        lastFlush = Date()
        guard !buffer.isEmpty, let handle else { return }
        do {
            try handle.write(contentsOf: Data(buffer.utf8))
            try handle.synchronize()
            buffer = ""
        } catch {
            print("TrackWriter flush 失败：\(error)")
        }
    }

    func close() {
        flush()
        try? handle?.close()
        handle = nil
    }
}
