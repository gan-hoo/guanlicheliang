import Foundation
import SwiftData

/// 用车费用
@Model
final class Expense {
    var id: UUID = UUID()
    var vehicleID: UUID? = nil
    var categoryID: UUID? = nil
    var date: Date = Date()
    var amount: Double = 0
    /// 里程表读数（km，可选）
    var odometer: Double? = nil
    var merchant: String = ""
    var notes: String = ""
    @Attribute(.externalStorage) var receiptData: Data? = nil
    /// 周期（月），0 表示非周期性费用
    var recurrenceMonths: Int = 0
    /// 下次到期日（周期性费用）
    var dueDate: Date? = nil
    /// 到期前几天提醒
    var remindDaysBefore: Int = 14
    var reminderEnabled: Bool = false
    /// 已续费（不再提醒）
    var renewed: Bool = false

    init(vehicleID: UUID? = nil, categoryID: UUID? = nil, date: Date = Date(), amount: Double = 0) {
        self.id = UUID()
        self.vehicleID = vehicleID
        self.categoryID = categoryID
        self.date = date
        self.amount = amount
    }
}

extension Expense {
    var isRecurring: Bool { recurrenceMonths > 0 }
}
