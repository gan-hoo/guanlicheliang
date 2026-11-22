import Foundation
import SwiftData

/// 保养提醒：按日期或按里程（例如每 10,000 km 或每 12 个月）
@Model
final class MaintenanceReminder {
    var id: UUID = UUID()
    var vehicleID: UUID? = nil
    var title: String = ""
    /// 间隔里程（km）
    var intervalKm: Double? = nil
    /// 间隔月数
    var intervalMonths: Int? = nil
    /// 上次完成时间与里程
    var lastDoneDate: Date = Date()
    var lastDoneOdometer: Double? = nil
    var isEnabled: Bool = true
    var notes: String = ""
    /// 已针对哪个「到期里程」发过通知（避免重复提醒）
    var notifiedDueOdometer: Double? = nil

    init(vehicleID: UUID?, title: String) {
        self.id = UUID()
        self.vehicleID = vehicleID
        self.title = title
        self.lastDoneDate = Date()
    }
}

extension MaintenanceReminder {
    var dueDate: Date? {
        guard let months = intervalMonths, months > 0 else { return nil }
        return Calendar.current.date(byAdding: .month, value: months, to: lastDoneDate)
    }

    var dueOdometer: Double? {
        guard let km = intervalKm, km > 0, let last = lastDoneOdometer else { return nil }
        return last + km
    }
}
