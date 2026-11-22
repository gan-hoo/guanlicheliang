import Foundation
import SwiftData

// MARK: - 备份文件里的数据结构

struct VehicleDTO: Codable {
    var id: UUID
    var nickname: String
    var brand: String
    var modelName: String
    var year: Int?
    var plate: String
    var fuelTypeRaw: String
    var tankCapacity: Double?
    var purchaseDate: Date?
    var purchasePrice: Double?
    var initialOdometer: Double
    var initialOdometerDate: Date
    var odometerCalibration: Double?
    var odometerCalibrationDate: Date?
    var notes: String
    var hasPhoto: Bool
    var createdAt: Date
}

struct TripDTO: Codable {
    var id: UUID
    var vehicleID: UUID?
    var startDate: Date
    var endDate: Date
    var distance: Double
    var duration: Double
    var movingDuration: Double
    var maxSpeed: Double
    var averageMovingSpeed: Double
    var minAltitude: Double?
    var maxAltitude: Double?
    var elevationGain: Double
    var startLatitude: Double?
    var startLongitude: Double?
    var endLatitude: Double?
    var endLongitude: Double?
    var startAddress: String?
    var endAddress: String?
    var pointCount: Int
    var notes: String
}

struct FuelEntryDTO: Codable {
    var id: UUID
    var vehicleID: UUID?
    var date: Date
    var odometer: Double
    var liters: Double
    var pricePerLiter: Double
    var totalCost: Double
    var fuelTypeRaw: String
    var stationName: String
    var latitude: Double?
    var longitude: Double?
    var isFullTank: Bool
    var missedPrevious: Bool
    var notes: String
}

struct ExpenseDTO: Codable {
    var id: UUID
    var vehicleID: UUID?
    var categoryID: UUID?
    var date: Date
    var amount: Double
    var odometer: Double?
    var merchant: String
    var notes: String
    var hasReceipt: Bool
    var recurrenceMonths: Int
    var dueDate: Date?
    var remindDaysBefore: Int
    var reminderEnabled: Bool
    var renewed: Bool
}

struct CategoryDTO: Codable {
    var id: UUID
    var name: String
    var iconName: String
    var sortOrder: Int
}

struct ReminderDTO: Codable {
    var id: UUID
    var vehicleID: UUID?
    var title: String
    var intervalKm: Double?
    var intervalMonths: Int?
    var lastDoneDate: Date
    var lastDoneOdometer: Double?
    var isEnabled: Bool
    var notes: String
    var notifiedDueOdometer: Double?
}

struct BackupManifest: Codable {
    var formatVersion: Int
    var createdAt: Date
    var appVersion: String
    var currentVehicleID: UUID?
    var currencyCode: String
    var vehicles: [VehicleDTO]
    var trips: [TripDTO]
    var fuelEntries: [FuelEntryDTO]
    var expenses: [ExpenseDTO]
    var categories: [CategoryDTO]
    var reminders: [ReminderDTO]
}

struct BackupSummary {
    var vehicles: Int
    var trips: Int
    var fuelEntries: Int
    var expenses: Int
    var tracks: Int
    var photos: Int
    var createdAt: Date

    var text: String {
        "\(vehicles) 辆车 · \(trips) 段行程（\(tracks) 条轨迹）· \(fuelEntries) 条加油 · \(expenses) 条费用 · \(photos) 张照片"
    }
}

enum BackupError: LocalizedError {
    case invalidFile
    case unsupportedVersion(Int)
    case missingManifest
    case recording

    var errorDescription: String? {
        switch self {
        case .invalidFile: return "这不是「行车记录」的备份文件，或者文件已损坏。"
        case .unsupportedVersion(let v): return "备份文件版本 \(v) 不受支持，请更新 App。"
        case .missingManifest: return "备份文件缺少数据清单。"
        case .recording: return "正在记录行程，请先停止记录再恢复。"
        }
    }
}

// MARK: - 简单的单文件归档格式
// 文件头 "DRIVELOGBACKUP01"，之后每个条目：
// [UInt32 名称长度][名称 UTF-8][UInt8 是否压缩][UInt64 数据长度][数据]
// 文本条目用 LZFSE 压缩。

private enum Archive {
    static let magic = Data("DRIVELOGBACKUP01".utf8)

    final class Writer {
        private let handle: FileHandle

        init(url: URL) throws {
            FileManager.default.createFile(atPath: url.path, contents: nil)
            handle = try FileHandle(forWritingTo: url)
            try handle.write(contentsOf: Archive.magic)
        }

        func add(name: String, data: Data, compress: Bool) throws {
            var payload = data
            var compressed: UInt8 = 0
            if compress, !data.isEmpty, let packed = try? (data as NSData).compressed(using: .lzfse) as Data {
                payload = packed
                compressed = 1
            }
            let nameData = Data(name.utf8)
            var header = Data()
            header.append(littleEndian: UInt32(nameData.count))
            header.append(nameData)
            header.append(compressed)
            header.append(littleEndian: UInt64(payload.count))
            try handle.write(contentsOf: header)
            try handle.write(contentsOf: payload)
        }

        func close() throws {
            try handle.synchronize()
            try handle.close()
        }
    }

    /// 读出所有条目（名称 → 数据）
    static func read(url: URL) throws -> [String: Data] {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard data.count >= magic.count, data.prefix(magic.count) == magic else {
            throw BackupError.invalidFile
        }
        var entries: [String: Data] = [:]
        var offset = data.startIndex + magic.count
        while offset < data.endIndex {
            guard let nameLength = data.readUInt32(at: &offset) else { throw BackupError.invalidFile }
            guard offset + Int(nameLength) <= data.endIndex else { throw BackupError.invalidFile }
            let name = String(decoding: data[offset..<(offset + Int(nameLength))], as: UTF8.self)
            offset += Int(nameLength)
            guard offset < data.endIndex else { throw BackupError.invalidFile }
            let compressed = data[offset]
            offset += 1
            guard let length = data.readUInt64(at: &offset), offset + Int(length) <= data.endIndex else {
                throw BackupError.invalidFile
            }
            var payload = Data(data[offset..<(offset + Int(length))])
            offset += Int(length)
            if compressed == 1 {
                guard let unpacked = try? (payload as NSData).decompressed(using: .lzfse) as Data else {
                    throw BackupError.invalidFile
                }
                payload = unpacked
            }
            entries[name] = payload
        }
        return entries
    }
}

private extension Data {
    mutating func append(littleEndian value: UInt32) {
        var v = value.littleEndian
        Swift.withUnsafeBytes(of: &v) { append(contentsOf: $0) }
    }

    mutating func append(littleEndian value: UInt64) {
        var v = value.littleEndian
        Swift.withUnsafeBytes(of: &v) { append(contentsOf: $0) }
    }

    func readUInt32(at offset: inout Int) -> UInt32? {
        guard offset + 4 <= endIndex else { return nil }
        var value: UInt32 = 0
        for i in 0..<4 {
            value |= UInt32(self[offset + i]) << (8 * UInt32(i))
        }
        offset += 4
        return value
    }

    func readUInt64(at offset: inout Int) -> UInt64? {
        guard offset + 8 <= endIndex else { return nil }
        var value: UInt64 = 0
        for i in 0..<8 {
            value |= UInt64(self[offset + i]) << (8 * UInt64(i))
        }
        offset += 8
        return value
    }
}

// MARK: - 备份 / 恢复

@MainActor
enum BackupService {
    static let fileExtension = "drivelog"
    static let formatVersion = 1

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }

    /// 一键备份全部数据（车辆、加油、费用、行程、轨迹、照片）到 Documents/备份/
    static func createBackup(context: ModelContext) throws -> (url: URL, summary: BackupSummary) {
        let vehicles = try context.fetch(FetchDescriptor<Vehicle>())
        let trips = try context.fetch(FetchDescriptor<Trip>())
        let fuel = try context.fetch(FetchDescriptor<FuelEntry>())
        let expenses = try context.fetch(FetchDescriptor<Expense>())
        let categories = try context.fetch(FetchDescriptor<ExpenseCategory>())
        let reminders = try context.fetch(FetchDescriptor<MaintenanceReminder>())

        let manifest = BackupManifest(
            formatVersion: formatVersion,
            createdAt: Date(),
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "",
            currentVehicleID: AppSettings.currentVehicleID,
            currencyCode: AppSettings.currencyCode,
            vehicles: vehicles.map { v in
                VehicleDTO(id: v.id, nickname: v.nickname, brand: v.brand, modelName: v.modelName, year: v.year,
                           plate: v.plate, fuelTypeRaw: v.fuelTypeRaw, tankCapacity: v.tankCapacity,
                           purchaseDate: v.purchaseDate, purchasePrice: v.purchasePrice,
                           initialOdometer: v.initialOdometer, initialOdometerDate: v.initialOdometerDate,
                           odometerCalibration: v.odometerCalibration, odometerCalibrationDate: v.odometerCalibrationDate,
                           notes: v.notes, hasPhoto: v.photoData != nil, createdAt: v.createdAt)
            },
            trips: trips.map { t in
                TripDTO(id: t.id, vehicleID: t.vehicleID, startDate: t.startDate, endDate: t.endDate,
                        distance: t.distance, duration: t.duration, movingDuration: t.movingDuration,
                        maxSpeed: t.maxSpeed, averageMovingSpeed: t.averageMovingSpeed,
                        minAltitude: t.minAltitude, maxAltitude: t.maxAltitude, elevationGain: t.elevationGain,
                        startLatitude: t.startLatitude, startLongitude: t.startLongitude,
                        endLatitude: t.endLatitude, endLongitude: t.endLongitude,
                        startAddress: t.startAddress, endAddress: t.endAddress,
                        pointCount: t.pointCount, notes: t.notes)
            },
            fuelEntries: fuel.map { f in
                FuelEntryDTO(id: f.id, vehicleID: f.vehicleID, date: f.date, odometer: f.odometer, liters: f.liters,
                             pricePerLiter: f.pricePerLiter, totalCost: f.totalCost, fuelTypeRaw: f.fuelTypeRaw,
                             stationName: f.stationName, latitude: f.latitude, longitude: f.longitude,
                             isFullTank: f.isFullTank, missedPrevious: f.missedPrevious, notes: f.notes)
            },
            expenses: expenses.map { e in
                ExpenseDTO(id: e.id, vehicleID: e.vehicleID, categoryID: e.categoryID, date: e.date, amount: e.amount,
                           odometer: e.odometer, merchant: e.merchant, notes: e.notes, hasReceipt: e.receiptData != nil,
                           recurrenceMonths: e.recurrenceMonths, dueDate: e.dueDate, remindDaysBefore: e.remindDaysBefore,
                           reminderEnabled: e.reminderEnabled, renewed: e.renewed)
            },
            categories: categories.map { c in
                CategoryDTO(id: c.id, name: c.name, iconName: c.iconName, sortOrder: c.sortOrder)
            },
            reminders: reminders.map { r in
                ReminderDTO(id: r.id, vehicleID: r.vehicleID, title: r.title, intervalKm: r.intervalKm,
                            intervalMonths: r.intervalMonths, lastDoneDate: r.lastDoneDate,
                            lastDoneOdometer: r.lastDoneOdometer, isEnabled: r.isEnabled, notes: r.notes,
                            notifiedDueOdometer: r.notifiedDueOdometer)
            }
        )

        let stamp = Fmt.fileStamp.string(from: Date())
        let finalURL = AppPaths.backupsDirectory.appendingPathComponent("行车记录备份_\(stamp).\(fileExtension)")
        let tempURL = AppPaths.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".tmp")

        let writer = try Archive.Writer(url: tempURL)
        try writer.add(name: "manifest.json", data: try makeEncoder().encode(manifest), compress: true)

        var trackCount = 0
        for trip in trips {
            let url = TrackStore.url(for: trip.id)
            if let data = try? Data(contentsOf: url) {
                try writer.add(name: "tracks/\(trip.id.uuidString).csv", data: data, compress: true)
                trackCount += 1
            }
        }
        var photoCount = 0
        for vehicle in vehicles {
            if let photo = vehicle.photoData {
                try writer.add(name: "photos/vehicle-\(vehicle.id.uuidString).jpg", data: photo, compress: false)
                photoCount += 1
            }
        }
        for expense in expenses {
            if let photo = expense.receiptData {
                try writer.add(name: "photos/expense-\(expense.id.uuidString).jpg", data: photo, compress: false)
                photoCount += 1
            }
        }
        try writer.close()

        let fm = FileManager.default
        if fm.fileExists(atPath: finalURL.path) {
            try fm.removeItem(at: finalURL)
        }
        try fm.moveItem(at: tempURL, to: finalURL)

        let summary = BackupSummary(vehicles: vehicles.count, trips: trips.count, fuelEntries: fuel.count,
                                    expenses: expenses.count, tracks: trackCount, photos: photoCount,
                                    createdAt: manifest.createdAt)
        return (finalURL, summary)
    }

    /// 读取备份信息（不修改任何数据）
    static func inspect(url: URL) throws -> BackupSummary {
        let entries = try Archive.read(url: url)
        let manifest = try decodeManifest(entries)
        return BackupSummary(vehicles: manifest.vehicles.count, trips: manifest.trips.count,
                             fuelEntries: manifest.fuelEntries.count, expenses: manifest.expenses.count,
                             tracks: entries.keys.filter { $0.hasPrefix("tracks/") }.count,
                             photos: entries.keys.filter { $0.hasPrefix("photos/") }.count,
                             createdAt: manifest.createdAt)
    }

    private static func decodeManifest(_ entries: [String: Data]) throws -> BackupManifest {
        guard let data = entries["manifest.json"] else { throw BackupError.missingManifest }
        let manifest = try makeDecoder().decode(BackupManifest.self, from: data)
        guard manifest.formatVersion <= formatVersion else {
            throw BackupError.unsupportedVersion(manifest.formatVersion)
        }
        return manifest
    }

    /// 从备份完整恢复：先完整读取并校验备份，再清空现有数据，最后写入
    static func restore(from url: URL, context: ModelContext) throws -> BackupSummary {
        if TripRecorder.shared.isRecording { throw BackupError.recording }

        let entries = try Archive.read(url: url)
        let manifest = try decodeManifest(entries)

        // 1. 清空现有数据
        for item in try context.fetch(FetchDescriptor<Trip>()) { context.delete(item) }
        for item in try context.fetch(FetchDescriptor<FuelEntry>()) { context.delete(item) }
        for item in try context.fetch(FetchDescriptor<Expense>()) { context.delete(item) }
        for item in try context.fetch(FetchDescriptor<ExpenseCategory>()) { context.delete(item) }
        for item in try context.fetch(FetchDescriptor<MaintenanceReminder>()) { context.delete(item) }
        for item in try context.fetch(FetchDescriptor<Vehicle>()) { context.delete(item) }
        try context.save()

        let fm = FileManager.default
        for id in TrackStore.allTrackIDs() {
            TrackStore.delete(id)
        }
        if let exported = try? fm.contentsOfDirectory(at: AppPaths.tripExportsDirectory, includingPropertiesForKeys: nil) {
            for file in exported { try? fm.removeItem(at: file) }
        }

        // 2. 写入备份数据
        for d in manifest.vehicles {
            let v = Vehicle(nickname: d.nickname, brand: d.brand, modelName: d.modelName)
            v.id = d.id
            v.year = d.year
            v.plate = d.plate
            v.fuelTypeRaw = d.fuelTypeRaw
            v.tankCapacity = d.tankCapacity
            v.purchaseDate = d.purchaseDate
            v.purchasePrice = d.purchasePrice
            v.initialOdometer = d.initialOdometer
            v.initialOdometerDate = d.initialOdometerDate
            v.odometerCalibration = d.odometerCalibration
            v.odometerCalibrationDate = d.odometerCalibrationDate
            v.notes = d.notes
            v.createdAt = d.createdAt
            v.photoData = entries["photos/vehicle-\(d.id.uuidString).jpg"]
            context.insert(v)
        }
        for d in manifest.categories {
            let c = ExpenseCategory(name: d.name, iconName: d.iconName, sortOrder: d.sortOrder)
            c.id = d.id
            context.insert(c)
        }
        var trackCount = 0
        for d in manifest.trips {
            let t = Trip(id: d.id, vehicleID: d.vehicleID, startDate: d.startDate, endDate: d.endDate)
            t.distance = d.distance
            t.duration = d.duration
            t.movingDuration = d.movingDuration
            t.maxSpeed = d.maxSpeed
            t.averageMovingSpeed = d.averageMovingSpeed
            t.minAltitude = d.minAltitude
            t.maxAltitude = d.maxAltitude
            t.elevationGain = d.elevationGain
            t.startLatitude = d.startLatitude
            t.startLongitude = d.startLongitude
            t.endLatitude = d.endLatitude
            t.endLongitude = d.endLongitude
            t.startAddress = d.startAddress
            t.endAddress = d.endAddress
            t.pointCount = d.pointCount
            t.notes = d.notes
            context.insert(t)
            if let track = entries["tracks/\(d.id.uuidString).csv"] {
                try track.write(to: TrackStore.url(for: d.id), options: .atomic)
                trackCount += 1
            }
        }
        for d in manifest.fuelEntries {
            let f = FuelEntry(vehicleID: d.vehicleID, date: d.date)
            f.id = d.id
            f.odometer = d.odometer
            f.liters = d.liters
            f.pricePerLiter = d.pricePerLiter
            f.totalCost = d.totalCost
            f.fuelTypeRaw = d.fuelTypeRaw
            f.stationName = d.stationName
            f.latitude = d.latitude
            f.longitude = d.longitude
            f.isFullTank = d.isFullTank
            f.missedPrevious = d.missedPrevious
            f.notes = d.notes
            context.insert(f)
        }
        for d in manifest.expenses {
            let e = Expense(vehicleID: d.vehicleID, categoryID: d.categoryID, date: d.date, amount: d.amount)
            e.id = d.id
            e.odometer = d.odometer
            e.merchant = d.merchant
            e.notes = d.notes
            e.receiptData = entries["photos/expense-\(d.id.uuidString).jpg"]
            e.recurrenceMonths = d.recurrenceMonths
            e.dueDate = d.dueDate
            e.remindDaysBefore = d.remindDaysBefore
            e.reminderEnabled = d.reminderEnabled
            e.renewed = d.renewed
            context.insert(e)
        }
        for d in manifest.reminders {
            let r = MaintenanceReminder(vehicleID: d.vehicleID, title: d.title)
            r.id = d.id
            r.intervalKm = d.intervalKm
            r.intervalMonths = d.intervalMonths
            r.lastDoneDate = d.lastDoneDate
            r.lastDoneOdometer = d.lastDoneOdometer
            r.isEnabled = d.isEnabled
            r.notes = d.notes
            r.notifiedDueOdometer = d.notifiedDueOdometer
            context.insert(r)
        }
        try context.save()

        // 3. 设置
        UserDefaults.standard.set(true, forKey: AppSettings.didSeedCategoriesKey)
        AppSettings.currencyCode = manifest.currencyCode
        AppSettings.currentVehicleID = manifest.currentVehicleID
        SeedData.ensureCurrentVehicle(context: context)
        ReminderEngine.rescheduleAll(context: context)

        // 4. 后台重新生成每段行程的 GPX / CSV
        let tripKeys = manifest.trips.map { ($0.id, $0.startDate) }
        Task.detached(priority: .utility) {
            for (id, startDate) in tripKeys {
                let points = TrackStore.readPoints(for: id)
                TripExporter.export(id: id, startDate: startDate, points: points)
            }
        }

        return BackupSummary(vehicles: manifest.vehicles.count, trips: manifest.trips.count,
                             fuelEntries: manifest.fuelEntries.count, expenses: manifest.expenses.count,
                             tracks: trackCount,
                             photos: entries.keys.filter { $0.hasPrefix("photos/") }.count,
                             createdAt: manifest.createdAt)
    }

    /// Documents/备份/ 里已有的备份文件（新的在前）
    static func existingBackups() -> [URL] {
        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(at: AppPaths.backupsDirectory,
                                                 includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey])) ?? []
        return files
            .filter { $0.pathExtension == fileExtension }
            .sorted { a, b in
                let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return da > db
            }
    }

    static func fileSize(_ url: URL) -> String {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }
}
