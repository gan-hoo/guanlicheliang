import Foundation
import SwiftData
import CostKit

/// 给旧费用补上费用类型。
/// 只处理 costTypeRaw 为 nil 的记录（升级前的数据、旧备份恢复的数据），已经有类型的不动，所以反复执行也安全。
/// 规则：按分类名称推荐（CostType.suggested），匹配不到的算运行费用；
/// 固定费用的摊销月数：原来设置了周期的用周期月数，否则 12 个月。
@MainActor
enum CostTypeMigration {
    static func run(context: ModelContext) {
        let descriptor = FetchDescriptor<Expense>(predicate: #Predicate { $0.costTypeRaw == nil })
        guard let expenses = try? context.fetch(descriptor), !expenses.isEmpty else { return }
        let categories = (try? context.fetch(FetchDescriptor<ExpenseCategory>())) ?? []
        let names = Dictionary(categories.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })

        for expense in expenses {
            let type = CostType.suggested(forCategoryName: expense.categoryID.flatMap { names[$0] })
            expense.costType = type
            if type == .fixed && expense.coverageMonths == nil {
                expense.coverageMonths = expense.recurrenceMonths > 0 ? expense.recurrenceMonths : CostType.defaultCoverageMonths
            }
        }
        try? context.save()
    }
}
