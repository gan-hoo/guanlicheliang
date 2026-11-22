import SwiftUI
import SwiftData
import Charts

struct ExpenseListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Expense.date, order: .reverse) private var expenses: [Expense]
    @Query(sort: \ExpenseCategory.sortOrder) private var categories: [ExpenseCategory]
    @Query(sort: \Vehicle.createdAt) private var vehicles: [Vehicle]
    @Query private var reminders: [MaintenanceReminder]
    @Query private var trips: [Trip]
    @Query private var fuelEntries: [FuelEntry]
    @AppStorage(AppSettings.currentVehicleKey) private var currentVehicleIDString: String = ""
    @AppStorage(AppSettings.currencyKey) private var currencyCode: String = AppSettings.defaultCurrency

    @State private var filterVehicleID: UUID?
    @State private var showAdd = false
    @State private var editingExpense: Expense?
    @State private var renewingExpense: Expense?
    @State private var showCategories = false

    private var filtered: [Expense] {
        guard let filterVehicleID else { return expenses }
        return expenses.filter { $0.vehicleID == filterVehicleID }
    }

    private var defaultVehicleID: UUID? {
        if let filterVehicleID { return filterVehicleID }
        if let id = UUID(uuidString: currentVehicleIDString), vehicles.contains(where: { $0.id == id }) { return id }
        return vehicles.first?.id
    }

    var body: some View {
        let upcoming = ReminderEngine.upcomingItems(expenses: filtered, reminders: [], categories: categories,
                                                    vehicles: vehicles, trips: trips, fuel: fuelEntries)
        NavigationStack {
            List {
                Group {
                    if vehicles.isEmpty {
                        ContentUnavailableView("先添加一辆车", systemImage: "car",
                                               description: Text("在「车辆/设置」里添加车辆后即可记录费用。"))
                    } else {
                        Section {
                        } header: {
                            VStack(alignment: .leading, spacing: 16) {
                                summary
                                MonthlyExpenseChart(expenses: filtered, categories: categories)
                            }
                            .glassListHeader(topSpacing: Theme.firstCardTopSpacing)
                        }

                        if !upcoming.isEmpty {
                            Section("即将到期") {
                                ForEach(upcoming) { item in
                                    if let expense = expenses.first(where: { $0.id == item.id }) {
                                        HStack {
                                            UpcomingRow(item: item)
                                            Spacer()
                                            Button("续费") {
                                                renewingExpense = expense
                                            }
                                            .glassButtonStyle()
                                            .controlSize(.small)
                                        }
                                    }
                                }
                            }
                        }

                        if filtered.isEmpty {
                            Section {
                                Text("还没有费用记录，点右上角「+」添加。")
                                    .foregroundStyle(.secondary)
                            }
                        }

                        ForEach(monthGroups) { group in
                            Section {
                                ForEach(group.items) { expense in
                                    Button {
                                        editingExpense = expense
                                    } label: {
                                        ExpenseRow(expense: expense,
                                                   category: categories.first(where: { $0.id == expense.categoryID }),
                                                   vehicleName: vehicles.count > 1 ? vehicles.first(where: { $0.id == expense.vehicleID })?.displayName : nil)
                                    }
                                    .buttonStyle(.plain)
                                    .swipeActions(edge: .leading) {
                                        if expense.isRecurring && !expense.renewed {
                                            Button {
                                                renewingExpense = expense
                                            } label: {
                                                Label("续费", systemImage: "arrow.clockwise")
                                            }
                                            .tint(.blue)
                                        }
                                    }
                                }
                                .onDelete { offsets in
                                    for index in offsets {
                                        context.delete(group.items[index])
                                    }
                                    try? context.save()
                                    ReminderEngine.rescheduleAll(context: context)
                                }
                            } header: {
                                HStack {
                                    Text(group.title)
                                    Spacer()
                                    Text(Fmt.money(group.total))
                                }
                            }
                        }
                    }
                }
                .listRowBackground(Theme.rowFill)
            }
            .appBackground()
            .navigationTitle("费用")
            .pageHeader("费用") {
                HeaderButtonGroup {
                    NavigationLink {
                        StatsView(initialVehicleID: filterVehicleID ?? defaultVehicleID)
                    } label: {
                        HeaderIcon(systemName: "chart.pie")
                    }
                    .buttonStyle(.plain)
                }
                HeaderButtonGroup {
                    Menu {
                        Picker("车辆", selection: $filterVehicleID) {
                            Text("全部车辆").tag(UUID?.none)
                            ForEach(vehicles) { v in
                                Text(v.displayName).tag(UUID?.some(v.id))
                            }
                        }
                        Button {
                            showCategories = true
                        } label: {
                            Label("管理分类", systemImage: "square.grid.2x2")
                        }
                    } label: {
                        HeaderIcon(systemName: filterVehicleID == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                    }
                    Button {
                        showAdd = true
                    } label: {
                        HeaderIcon(systemName: "plus")
                    }
                    .buttonStyle(.plain)
                    .disabled(vehicles.isEmpty)
                }
            }
            .navigationDestination(isPresented: $showCategories) {
                ExpenseCategoryManagerView()
            }
            .sheet(isPresented: $showAdd) {
                ExpenseEditView(expense: nil, defaultVehicleID: defaultVehicleID)
            }
            .sheet(item: $editingExpense) { expense in
                ExpenseEditView(expense: expense, defaultVehicleID: expense.vehicleID)
            }
            .sheet(item: $renewingExpense) { expense in
                ExpenseEditView(expense: nil, defaultVehicleID: expense.vehicleID, renewing: expense)
            }
        }
    }

    private var summary: some View {
        let calendar = Calendar.current
        let now = Date()
        let thisMonth = filtered.filter { calendar.isDate($0.date, equalTo: now, toGranularity: .month) }.reduce(0) { $0 + $1.amount }
        let thisYear = filtered.filter { calendar.isDate($0.date, equalTo: now, toGranularity: .year) }.reduce(0) { $0 + $1.amount }
        return HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("本月费用（不含油费）")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Text(Fmt.money(thisMonth))
                    .font(.numeric(40, weight: .bold))
                    .foregroundStyle(Theme.moneyGradient)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .contentTransition(.numericText())
                Text("今年 \(Fmt.money(thisYear))")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            MetricIcon(systemName: "creditcard.fill", tint: Theme.money, size: 44)
        }
        .animation(.snappy, value: thisMonth)
    }

    private var monthGroups: [ExpenseMonthGroup] {
        let calendar = Calendar.current
        var groups: [ExpenseMonthGroup] = []
        for expense in filtered {
            let comps = calendar.dateComponents([.year, .month], from: expense.date)
            let key = "\(comps.year ?? 0)-\(comps.month ?? 0)"
            if let last = groups.last, last.id == key {
                groups[groups.count - 1].items.append(expense)
            } else {
                groups.append(ExpenseMonthGroup(id: key, title: Fmt.monthTitle.string(from: expense.date), items: [expense]))
            }
        }
        return groups
    }
}

struct ExpenseMonthGroup: Identifiable {
    let id: String
    let title: String
    var items: [Expense]

    var total: Double { items.reduce(0) { $0 + $1.amount } }
}

struct ExpenseRow: View {
    let expense: Expense
    let category: ExpenseCategory?
    let vehicleName: String?

    var body: some View {
        HStack(spacing: 12) {
            CategoryIcon(iconName: category?.iconName ?? "questionmark.circle",
                         color: CategoryPalette.color(for: category))
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(category?.name ?? "未分类")
                        .font(.headline)
                    if expense.isRecurring {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }
                    Spacer()
                    Text(Fmt.money(expense.amount))
                        .font(.headline)
                        .monospacedDigit()
                }
                let note = expense.notes.trimmingCharacters(in: .whitespacesAndNewlines)
                HStack {
                    Text(Fmt.dateShort.string(from: expense.date))
                    if !expense.merchant.isEmpty {
                        Text("· \(expense.merchant)")
                            .lineLimit(1)
                    }
                    if !note.isEmpty {
                        Text("· \(note)")
                            .lineLimit(1)
                    }
                    if expense.receiptData != nil {
                        Image(systemName: "paperclip")
                    }
                    Spacer()
                    if let vehicleName {
                        Text(vehicleName)
                            .lineLimit(1)
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                if let due = expense.dueDate, expense.isRecurring {
                    Text(expense.renewed ? "已续费" : "到期 \(Fmt.dateFull.string(from: due))")
                        .font(.caption)
                        .foregroundStyle(expense.renewed ? Color.secondary : Color.blue)
                }
            }
        }
        .contentShape(Rectangle())
        .padding(.vertical, 2)
    }
}

struct CategoryIcon: View {
    let iconName: String
    let color: Color
    var size: CGFloat = 34

    var body: some View {
        Image(systemName: iconName)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous).fill(color))
    }
}

/// 分类颜色：按排序位置取色，保证同一分类在各处颜色一致
enum CategoryPalette {
    static let colors: [Color] = [
        Color(red: 0.20, green: 0.47, blue: 0.95),
        Color(red: 0.93, green: 0.33, blue: 0.31),
        Color(red: 0.36, green: 0.36, blue: 0.40),
        Color(red: 0.16, green: 0.68, blue: 0.47),
        Color(red: 0.58, green: 0.36, blue: 0.85),
        Color(red: 0.98, green: 0.62, blue: 0.10),
        Color(red: 0.11, green: 0.64, blue: 0.78),
        Color(red: 0.85, green: 0.30, blue: 0.60),
        Color(red: 0.30, green: 0.75, blue: 0.90),
        Color(red: 0.80, green: 0.15, blue: 0.20),
        Color(red: 0.55, green: 0.45, blue: 0.30),
        Color(red: 0.40, green: 0.55, blue: 0.20),
        Color(red: 0.55, green: 0.55, blue: 0.60)
    ]

    static let fuelColor = Theme.fuel

    static func color(for category: ExpenseCategory?) -> Color {
        guard let category else { return .gray }
        return colors[abs(category.sortOrder) % colors.count]
    }
}

struct UpcomingRow: View {
    let item: UpcomingItem

    var body: some View {
        HStack(spacing: 10) {
            MetricIcon(systemName: item.kind == .expense ? "calendar.badge.exclamationmark" : "wrench.and.screwdriver.fill",
                       tint: item.isOverdue ? Theme.maxSpeed : Theme.speed,
                       size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                Text(item.detail)
                    .font(.caption)
                    .foregroundStyle(item.isOverdue ? Color.red : Color.secondary)
            }
        }
    }
}

/// 最近 12 个月的费用（按分类堆叠）
struct MonthlyExpenseChart: View {
    let expenses: [Expense]
    let categories: [ExpenseCategory]

    private struct Bar: Identifiable {
        let id = UUID()
        let month: Date
        let category: String
        let amount: Double
    }

    var body: some View {
        let calendar = Calendar.current
        let thisMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: Date())) ?? Date()
        let start = calendar.date(byAdding: .month, value: -11, to: thisMonth) ?? thisMonth
        var sums: [String: [Date: Double]] = [:]
        for expense in expenses where expense.date >= start {
            let month = calendar.date(from: calendar.dateComponents([.year, .month], from: expense.date)) ?? expense.date
            let name = categories.first(where: { $0.id == expense.categoryID })?.name ?? "未分类"
            sums[name, default: [:]][month, default: 0] += expense.amount
        }
        let bars = sums.flatMap { name, byMonth in
            byMonth.map { Bar(month: $0.key, category: name, amount: $0.value) }
        }
        var names: [String] = []
        for name in categories.map(\.name) + ["未分类"] where sums[name] != nil && !names.contains(name) {
            names.append(name)
        }
        let colors = names.map { name in
            CategoryPalette.color(for: categories.first(where: { $0.name == name }))
        }

        return Group {
            if bars.isEmpty {
                Text("最近 12 个月没有费用")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 60)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("最近 12 个月")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Chart(bars) { bar in
                        BarMark(x: .value("月份", bar.month, unit: .month),
                                y: .value("金额", bar.amount),
                                width: .ratio(0.62))
                            .foregroundStyle(by: .value("分类", bar.category))
                            .cornerRadius(4)
                    }
                    .chartForegroundStyleScale(domain: names, range: colors)
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .month, count: 2)) { _ in
                            AxisGridLine()
                            AxisValueLabel(format: .dateTime.month(.defaultDigits))
                        }
                    }
                    .chartLegend(position: .bottom, alignment: .leading)
                    .frame(height: 200)
                }
            }
        }
    }
}
