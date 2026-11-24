import Foundation
import SwiftData
import CostKit

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
    /// 费用类型（CostType 的 rawValue：running / fixed / oneOff）。
    /// 可选字段，旧数据升级后为 nil，启动时由 CostTypeMigration 按分类补上
    var costTypeRaw: String? = nil
    /// 固定费用的覆盖月数（按月摊销），nil 按 12 个月
    var coverageMonths: Int? = nil

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

    /// 费用类型；没设置时按运行费用算
    var costType: CostType {
        get { CostType(rawValue: costTypeRaw ?? "") ?? .running }
        set { costTypeRaw = newValue.rawValue }
    }

    /// 摊销月数（至少 1）
    var coverage: Int { max(1, coverageMonths ?? CostType.defaultCoverageMonths) }

    /// 给 CostKit 用的费用数据
    var costItem: CostItem {
        CostItem(date: date, amount: amount, type: costType, coverageMonths: coverage)
    }
}
