import SwiftUI

// 第一阶段占位：加油、费用、统计、备份等页面在第二阶段实现

struct FuelListView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView("加油记录", systemImage: "fuelpump", description: Text("即将推出"))
                .navigationTitle("加油")
        }
    }
}

struct ExpenseListView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView("用车费用", systemImage: "creditcard", description: Text("即将推出"))
                .navigationTitle("费用")
        }
    }
}

struct StatsView: View {
    var initialVehicleID: UUID? = nil

    var body: some View {
        ContentUnavailableView("统计", systemImage: "chart.pie", description: Text("即将推出"))
    }
}

struct ExpenseCategoryManagerView: View {
    var body: some View {
        ContentUnavailableView("费用分类", systemImage: "square.grid.2x2", description: Text("即将推出"))
    }
}

struct MaintenanceListView: View {
    var body: some View {
        ContentUnavailableView("保养提醒", systemImage: "bell.badge", description: Text("即将推出"))
    }
}

struct ExportCenterView: View {
    var body: some View {
        ContentUnavailableView("导出 CSV", systemImage: "tablecells", description: Text("即将推出"))
    }
}

struct BackupView: View {
    var body: some View {
        ContentUnavailableView("备份与恢复", systemImage: "externaldrive", description: Text("即将推出"))
    }
}
