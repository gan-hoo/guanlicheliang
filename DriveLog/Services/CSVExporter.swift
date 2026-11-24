import Foundation
import SwiftData
import CostKit

/// 加油 / 费用 / 行程概要导出成 CSV（UTF-8 带 BOM，Windows Excel 打开中文不乱码）
@MainActor
enum CSVExporter {
    private static let dateTime: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()

    private static let dateOnly: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    nonisolated static func escape(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r") {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }

    private static func num(_ v: Double?, _ decimals: Int) -> String {
        guard let v else { return "" }
        return String(format: "%.\(decimals)f", v)
    }

    private static func write(_ rows: [[String]], name: String) throws -> URL {
        let text = rows.map { row in row.map { CSVExporter.escape($0) }.joined(separator: ",") }.joined(separator: "\r\n") + "\r\n"
        var data = Data([0xEF, 0xBB, 0xBF])
        data.append(Data(text.utf8))
        let stamp = Fmt.fileStamp.string(from: Date())
        let url = AppPaths.dataExportsDirectory.appendingPathComponent("\(name)_\(stamp).csv")
        try data.write(to: url, options: .atomic)
        return url
    }

    static func exportFuel(context: ModelContext) throws -> URL {
        let entries = (try? context.fetch(FetchDescriptor<FuelEntry>(sortBy: [SortDescriptor(\.date)]))) ?? []
        let vehicles = (try? context.fetch(FetchDescriptor<Vehicle>())) ?? []
        var economy: [UUID: Double] = [:]
        for vehicle in vehicles {
            let analysis = FuelEconomy.analyze(entries: entries.filter { $0.vehicleID == vehicle.id })
            economy.merge(analysis.economyByEntryID) { a, _ in a }
        }
        var rows: [[String]] = [["日期", "车辆", "里程表(km)", "加油量(L)", "单价", "总价", "货币", "燃油类型", "加油站", "纬度", "经度", "是否加满", "上次漏记", "油耗(L/100km)", "备注"]]
        let currency = AppSettings.currencyCode
        for e in entries {
            rows.append([
                dateTime.string(from: e.date),
                vehicles.first(where: { $0.id == e.vehicleID })?.displayName ?? "",
                num(e.odometer, 0),
                num(e.liters, 2),
                num(e.pricePerLiter, 3),
                num(e.totalCost, 2),
                currency,
                e.fuelType.displayName,
                e.stationName,
                num(e.latitude, 6),
                num(e.longitude, 6),
                e.isFullTank ? "是" : "否",
                e.missedPrevious ? "是" : "否",
                num(economy[e.id], 2),
                e.notes
            ])
        }
        return try write(rows, name: "加油记录")
    }

    static func exportExpenses(context: ModelContext) throws -> URL {
        let expenses = (try? context.fetch(FetchDescriptor<Expense>(sortBy: [SortDescriptor(\.date)]))) ?? []
        let vehicles = (try? context.fetch(FetchDescriptor<Vehicle>())) ?? []
        let categories = (try? context.fetch(FetchDescriptor<ExpenseCategory>())) ?? []
        let currency = AppSettings.currencyCode
        var rows: [[String]] = [["日期", "车辆", "分类", "金额", "货币", "里程表(km)", "商家", "周期(月)", "到期日", "备注", "费用类型", "摊销(月)"]]
        for e in expenses {
            rows.append([
                dateOnly.string(from: e.date),
                vehicles.first(where: { $0.id == e.vehicleID })?.displayName ?? "",
                categories.first(where: { $0.id == e.categoryID })?.name ?? "未分类",
                num(e.amount, 2),
                currency,
                num(e.odometer, 0),
                e.merchant,
                e.recurrenceMonths > 0 ? "\(e.recurrenceMonths)" : "",
                e.dueDate.map { dateOnly.string(from: $0) } ?? "",
                e.notes,
                e.costType.displayName,
                e.costType == .fixed ? "\(e.coverage)" : ""
            ])
        }
        return try write(rows, name: "用车费用")
    }

    static func exportTrips(context: ModelContext) throws -> URL {
        let trips = (try? context.fetch(FetchDescriptor<Trip>(sortBy: [SortDescriptor(\.startDate)]))) ?? []
        let vehicles = (try? context.fetch(FetchDescriptor<Vehicle>())) ?? []
        var rows: [[String]] = [["开始", "结束", "车辆", "距离(km)", "总时长(分钟)", "行驶时长(分钟)", "行驶均速(km/h)", "最高速度(km/h)", "最低海拔(m)", "最高海拔(m)", "累计爬升(m)", "起点", "终点", "备注"]]
        for t in trips {
            rows.append([
                dateTime.string(from: t.startDate),
                dateTime.string(from: t.endDate),
                vehicles.first(where: { $0.id == t.vehicleID })?.displayName ?? "",
                num(t.distance / 1000, 2),
                num(t.duration / 60, 1),
                num(t.movingDuration / 60, 1),
                num(t.averageMovingSpeed * 3.6, 1),
                num(t.maxSpeed * 3.6, 1),
                num(t.minAltitude, 0),
                num(t.maxAltitude, 0),
                num(t.elevationGain, 0),
                t.startAddress ?? "",
                t.endAddress ?? "",
                t.notes
            ])
        }
        return try write(rows, name: "行程概要")
    }
}
