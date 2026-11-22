import Foundation
import SwiftData

@MainActor
enum SeedData {
    /// 默认费用分类：名称 + SF Symbol
    static let defaultCategories: [(name: String, icon: String)] = [
        ("保养", "wrench.and.screwdriver"),
        ("维修", "hammer"),
        ("轮胎", "circle.circle"),
        ("保险", "checkmark.shield"),
        ("注册费 / rego", "doc.text"),
        ("年检", "checkmark.seal"),
        ("停车", "parkingsign.circle"),
        ("过路费", "road.lanes"),
        ("洗车", "drop"),
        ("罚款", "exclamationmark.triangle"),
        ("配件 / 改装", "gearshape.2"),
        ("贷款", "banknote"),
        ("其他", "ellipsis.circle")
    ]

    static func ensureDefaults(context: ModelContext) {
        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: AppSettings.didSeedCategoriesKey) {
            let count = (try? context.fetchCount(FetchDescriptor<ExpenseCategory>())) ?? 0
            if count == 0 {
                for (index, item) in defaultCategories.enumerated() {
                    context.insert(ExpenseCategory(name: item.name, iconName: item.icon, sortOrder: index))
                }
            }
            defaults.set(true, forKey: AppSettings.didSeedCategoriesKey)
        }
        ensureCurrentVehicle(context: context)
        try? context.save()
    }

    /// 当前车辆无效时自动选第一辆
    static func ensureCurrentVehicle(context: ModelContext) {
        let vehicles = (try? context.fetch(FetchDescriptor<Vehicle>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
        if let current = AppSettings.currentVehicleID, vehicles.contains(where: { $0.id == current }) {
            return
        }
        AppSettings.currentVehicleID = vehicles.first?.id
    }
}
