import Foundation
import SwiftData

/// 一条计划中的本地通知（值类型，方便跨线程传给通知中心）
struct PlannedNotification: Sendable {
    let identifier: String
    let title: String
    let body: String
    let date: Date
}

/// 到期提醒项（首页 / 费用页展示用）
struct UpcomingItem: Identifiable {
    enum Kind {
        case expense
        case maintenance
    }

    let id: UUID
    let kind: Kind
    let title: String
    let detail: String
    let vehicleID: UUID?
    /// 越小越紧急：剩余天数（或按里程折算）
    let urgency: Double
    let isOverdue: Bool
}

/// 提醒引擎：
/// - 周期性费用（保险、注册费…）：到期前 N 天 + 到期当天 09:00 本地通知
/// - 保养：按日期（到期前 7 天 + 当天）或按里程（剩余 ≤ 300 km 时立即通知一次）
@MainActor
enum ReminderEngine {
    static let notificationPrefix = "due-"
    static let mileageWarningKm: Double = 300

    /// 保存行程后：检查按里程的保养提醒
    static func tripSaved(context: ModelContext) {
        checkMileageReminders(context: context)
    }

    /// 重新计划所有按日期的提醒，并检查按里程的保养提醒
    static func rescheduleAll(context: ModelContext) {
        let expenses = (try? context.fetch(FetchDescriptor<Expense>())) ?? []
        let reminders = (try? context.fetch(FetchDescriptor<MaintenanceReminder>())) ?? []
        let vehicles = (try? context.fetch(FetchDescriptor<Vehicle>())) ?? []
        let categories = (try? context.fetch(FetchDescriptor<ExpenseCategory>())) ?? []

        var planned: [PlannedNotification] = []
        let calendar = Calendar.current

        for expense in expenses where expense.reminderEnabled && !expense.renewed {
            guard let due = expense.dueDate else { continue }
            let vehicleName = vehicles.first(where: { $0.id == expense.vehicleID })?.displayName ?? "未指定车辆"
            let categoryName = categories.first(where: { $0.id == expense.categoryID })?.name ?? "费用"
            let what = expense.merchant.isEmpty ? categoryName : "\(categoryName)（\(expense.merchant)）"
            let dueText = Fmt.dateFull.string(from: due)
            if let before = calendar.date(byAdding: .day, value: -max(0, expense.remindDaysBefore), to: due) {
                planned.append(PlannedNotification(
                    identifier: "\(notificationPrefix)expense-\(expense.id.uuidString)-before",
                    title: "\(categoryName)即将到期",
                    body: "\(vehicleName) · \(what) 将于 \(dueText) 到期，上次金额 \(Fmt.money(expense.amount))。",
                    date: atNineAM(before)))
            }
            planned.append(PlannedNotification(
                identifier: "\(notificationPrefix)expense-\(expense.id.uuidString)-due",
                title: "\(categoryName)今天到期",
                body: "\(vehicleName) · \(what) 今天（\(dueText)）到期。续费后在「费用」里点「续费」记录新的一期。",
                date: atNineAM(due)))
        }

        for reminder in reminders where reminder.isEnabled {
            guard let due = reminder.dueDate else { continue }
            let vehicleName = vehicles.first(where: { $0.id == reminder.vehicleID })?.displayName ?? "未指定车辆"
            if let before = calendar.date(byAdding: .day, value: -7, to: due) {
                planned.append(PlannedNotification(
                    identifier: "\(notificationPrefix)maint-\(reminder.id.uuidString)-before",
                    title: "保养提醒：\(reminder.title)",
                    body: "\(vehicleName) 将于 \(Fmt.dateFull.string(from: due)) 到期（每 \(reminder.intervalMonths ?? 0) 个月）。",
                    date: atNineAM(before)))
            }
            planned.append(PlannedNotification(
                identifier: "\(notificationPrefix)maint-\(reminder.id.uuidString)-due",
                title: "保养到期：\(reminder.title)",
                body: "\(vehicleName) 今天到了保养时间。完成后在「保养提醒」里点「标记已完成」。",
                date: atNineAM(due)))
        }

        let future = planned.filter { $0.date > Date() }
        NotificationManager.shared.replacePending(prefix: notificationPrefix, with: future)
        checkMileageReminders(context: context)
    }

    /// 按里程的保养：剩余 ≤ 300 km 时立即通知一次（每个到期周期只通知一次）
    static func checkMileageReminders(context: ModelContext) {
        let reminders = (try? context.fetch(FetchDescriptor<MaintenanceReminder>())) ?? []
        guard reminders.contains(where: { $0.isEnabled && $0.dueOdometer != nil }) else { return }
        let vehicles = (try? context.fetch(FetchDescriptor<Vehicle>())) ?? []
        let trips = (try? context.fetch(FetchDescriptor<Trip>())) ?? []
        let fuel = (try? context.fetch(FetchDescriptor<FuelEntry>())) ?? []
        let expenses = (try? context.fetch(FetchDescriptor<Expense>())) ?? []
        var changed = false

        for reminder in reminders where reminder.isEnabled {
            guard let dueOdometer = reminder.dueOdometer,
                  let vehicle = vehicles.first(where: { $0.id == reminder.vehicleID }) else { continue }
            if reminder.notifiedDueOdometer == dueOdometer { continue }
            let current = OdometerService.estimate(vehicle: vehicle, trips: trips, fuel: fuel, expenses: expenses)
            let remaining = dueOdometer - current
            guard remaining <= mileageWarningKm else { continue }
            let title = remaining <= 0 ? "保养已到期：\(reminder.title)" : "保养即将到期：\(reminder.title)"
            let body = remaining <= 0
                ? "\(vehicle.displayName) 估算里程 \(Fmt.odometer(current))，已超过保养里程 \(Fmt.odometer(dueOdometer))。"
                : "\(vehicle.displayName) 估算里程 \(Fmt.odometer(current))，还有约 \(Fmt.odometer(remaining)) 到保养里程 \(Fmt.odometer(dueOdometer))。"
            NotificationManager.shared.post(title: title, body: body, identifier: "maint-km-\(reminder.id.uuidString)")
            reminder.notifiedDueOdometer = dueOdometer
            changed = true
        }
        if changed {
            try? context.save()
        }
    }

    /// 即将到期的项目：周期性费用（60 天内）、保养（30 天内或 1000 km 内）
    static func upcomingItems(expenses: [Expense],
                              reminders: [MaintenanceReminder],
                              categories: [ExpenseCategory],
                              vehicles: [Vehicle],
                              trips: [Trip],
                              fuel: [FuelEntry]) -> [UpcomingItem] {
        var items: [UpcomingItem] = []
        let now = Date()
        let calendar = Calendar.current

        for expense in expenses where expense.isRecurring && !expense.renewed {
            guard let due = expense.dueDate else { continue }
            let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: due)).day ?? 0
            guard days <= 60 else { continue }
            let categoryName = categories.first(where: { $0.id == expense.categoryID })?.name ?? "费用"
            let vehicleName = vehicles.first(where: { $0.id == expense.vehicleID })?.displayName ?? ""
            let detail = days < 0 ? "已过期 \(-days) 天" : (days == 0 ? "今天到期" : "\(days) 天后到期")
            items.append(UpcomingItem(id: expense.id, kind: .expense,
                                      title: expense.merchant.isEmpty ? categoryName : "\(categoryName) · \(expense.merchant)",
                                      detail: "\(vehicleName) · \(Fmt.dateFull.string(from: due)) · \(detail)",
                                      vehicleID: expense.vehicleID,
                                      urgency: Double(days),
                                      isOverdue: days < 0))
        }

        for reminder in reminders where reminder.isEnabled {
            guard let vehicle = vehicles.first(where: { $0.id == reminder.vehicleID }) else { continue }
            let status = MaintenanceStatus(reminder: reminder, vehicle: vehicle, trips: trips, fuel: fuel, expenses: expenses)
            guard status.isDueSoon else { continue }
            items.append(UpcomingItem(id: reminder.id, kind: .maintenance,
                                      title: "保养 · \(reminder.title)",
                                      detail: "\(vehicle.displayName) · \(status.summary)",
                                      vehicleID: vehicle.id,
                                      urgency: status.urgency,
                                      isOverdue: status.isOverdue))
        }
        return items.sorted { $0.urgency < $1.urgency }
    }

    private static func atNineAM(_ date: Date) -> Date {
        Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: date) ?? date
    }
}

/// 保养提醒的当前状态
struct MaintenanceStatus {
    let daysRemaining: Int?
    let kmRemaining: Double?
    let currentOdometer: Double

    init(reminder: MaintenanceReminder, vehicle: Vehicle, trips: [Trip], fuel: [FuelEntry], expenses: [Expense]) {
        currentOdometer = OdometerService.estimate(vehicle: vehicle, trips: trips, fuel: fuel, expenses: expenses)
        if let due = reminder.dueDate {
            let calendar = Calendar.current
            daysRemaining = calendar.dateComponents([.day], from: calendar.startOfDay(for: Date()), to: calendar.startOfDay(for: due)).day
        } else {
            daysRemaining = nil
        }
        if let dueOdometer = reminder.dueOdometer {
            kmRemaining = dueOdometer - currentOdometer
        } else {
            kmRemaining = nil
        }
    }

    var isOverdue: Bool {
        (daysRemaining.map { $0 < 0 } ?? false) || (kmRemaining.map { $0 <= 0 } ?? false)
    }

    var isDueSoon: Bool {
        (daysRemaining.map { $0 <= 30 } ?? false) || (kmRemaining.map { $0 <= 1000 } ?? false)
    }

    /// 排序用：把里程折算成天（约 50 km/天）
    var urgency: Double {
        let byDays = daysRemaining.map { Double($0) } ?? Double.greatestFiniteMagnitude
        let byKm = kmRemaining.map { $0 / 50 } ?? Double.greatestFiniteMagnitude
        return min(byDays, byKm)
    }

    var summary: String {
        var parts: [String] = []
        if let days = daysRemaining {
            parts.append(days < 0 ? "已超期 \(-days) 天" : (days == 0 ? "今天到期" : "还剩 \(days) 天"))
        }
        if let km = kmRemaining {
            parts.append(km <= 0 ? "已超 \(Fmt.odometer(-km))" : "还剩 \(Fmt.odometer(km))")
        }
        return parts.isEmpty ? "未设置间隔" : parts.joined(separator: " · ")
    }
}
