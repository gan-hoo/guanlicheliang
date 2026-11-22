import Foundation
import SwiftData

/// 提醒引擎（第二阶段完善：周期性费用到期、保养按日期/里程）
@MainActor
enum ReminderEngine {
    static func tripSaved(context: ModelContext) {}
    static func rescheduleAll(context: ModelContext) {}
}
