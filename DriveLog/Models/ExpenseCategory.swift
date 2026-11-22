import Foundation
import SwiftData

/// 费用分类（可增删改名）
@Model
final class ExpenseCategory {
    var id: UUID = UUID()
    var name: String = ""
    var iconName: String = "tag"
    var sortOrder: Int = 0

    init(name: String, iconName: String, sortOrder: Int) {
        self.id = UUID()
        self.name = name
        self.iconName = iconName
        self.sortOrder = sortOrder
    }
}
