import SwiftUI
import SwiftData
import Charts

/// 统计：按月 / 按年 / 按车辆看总花费、分类占比、每公里成本、总里程、油耗趋势
struct StatsView: View {
    var initialVehicleID: UUID? = nil

    @Query(sort: \Vehicle.createdAt) private var vehicles: [Vehicle]
    @Query private var trips: [Trip]
    @Query private var fuelEntries: [FuelEntry]
    @Query private var expenses: [Expense]
    @Query(sort: \ExpenseCategory.sortOrder) private var categories: [ExpenseCategory]
    @AppStorage(AppSettings.currencyKey) private var currencyCode: String = AppSettings.defaultCurrency

    enum PeriodKind: String, CaseIterable, Identifiable {
        case month = "按月"
        case year = "按年"
        var id: String { rawValue }
    }

    @State private var vehicleID: UUID?
    @State private var periodKind: PeriodKind = .month
    @State private var anchor = Date()
    @State private var didInit = false

    private var calendar: Calendar { Calendar.current }

    private var interval: DateInterval {
        let component: Calendar.Component = periodKind == .month ? .month : .year
        return calendar.dateInterval(of: component, for: anchor) ?? DateInterval(start: anchor, duration: 1)
    }

    private var periodTitle: String {
        periodKind == .month ? Fmt.monthTitle.string(from: anchor) : Fmt.yearTitle.string(from: anchor)
    }

    private var canGoForward: Bool {
        interval.end <= Date()
    }

    var body: some View {
        let data = StatsData(vehicleID: vehicleID, interval: interval, periodKind: periodKind,
                             vehicles: vehicles, trips: trips, fuel: fuelEntries,
                             expenses: expenses, categories: categories)
        List {
            Section {
                Picker("周期", selection: $periodKind) {
                    ForEach(PeriodKind.allCases) { kind in
                        Text(kind.rawValue).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                HStack {
                    Button {
                        shift(-1)
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    Spacer()
                    Text(periodTitle)
                        .font(.headline)
                    Spacer()
                    Button {
                        shift(1)
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                    .disabled(!canGoForward)
                }
                .buttonStyle(.borderless)
                Picker("车辆", selection: $vehicleID) {
                    Text("全部车辆").tag(UUID?.none)
                    ForEach(vehicles) { v in
                        Text(v.displayName).tag(UUID?.some(v.id))
                    }
                }
            }

            Section("概览") {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    StatTile(title: "总花费", value: Fmt.money(data.totalCost), systemImage: "creditcard.fill", tint: Theme.money)
                    StatTile(title: "每公里成本", value: data.costPerKm.map { Fmt.money($0) } ?? "—", systemImage: "road.lanes", tint: Theme.distance)
                    StatTile(title: "油费", value: Fmt.money(data.fuelCost), systemImage: "fuelpump.fill", tint: Theme.fuel)
                    StatTile(title: "其他费用", value: Fmt.money(data.otherCost), systemImage: "wrench.and.screwdriver.fill", tint: Theme.duration)
                    StatTile(title: "总里程", value: Fmt.km(data.distanceKm), systemImage: "map.fill", tint: Theme.distance)
                    StatTile(title: "平均油耗", value: Fmt.economy(data.averageEconomy), systemImage: "gauge.with.dots.needle.33percent", tint: Theme.fuel)
                    StatTile(title: "加油量", value: String(format: "%.1f L", data.liters), systemImage: "drop.fill", tint: Theme.accentSecondary)
                    StatTile(title: "行程", value: "\(data.tripCount) 段", systemImage: "car.fill", tint: Theme.altitude)
                }
                .padding(.vertical, 4)
                Text("每公里成本 = （油费 + 其他费用）÷ 记录的行程里程。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("花费构成") {
                if data.breakdown.isEmpty {
                    Text("这段时间没有花费")
                        .foregroundStyle(.secondary)
                } else {
                    Chart(data.breakdown) { item in
                        SectorMark(angle: .value("金额", item.amount),
                                   innerRadius: .ratio(0.62),
                                   angularInset: 2)
                            .foregroundStyle(item.color)
                            .cornerRadius(3)
                    }
                    .frame(height: 220)
                    .chartBackground { _ in
                        VStack(spacing: 2) {
                            Text("合计")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(Fmt.money(data.totalCost))
                                .font(.headline)
                                .monospacedDigit()
                        }
                    }
                    ForEach(data.breakdown) { item in
                        HStack(spacing: 10) {
                            Circle()
                                .fill(item.color)
                                .frame(width: 10, height: 10)
                            Text(item.name)
                            Spacer()
                            Text(Fmt.money(item.amount))
                                .monospacedDigit()
                            Text(String(format: "%.0f%%", item.amount / max(data.totalCost, 0.0001) * 100))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 40, alignment: .trailing)
                        }
                    }
                }
            }

            Section(periodKind == .year ? "每月花费" : "最近 12 个月花费") {
                Chart(data.monthlyCosts) { item in
                    BarMark(x: .value("月份", item.month, unit: .month),
                            y: .value("金额", item.amount),
                            width: .ratio(0.62))
                        .foregroundStyle(by: .value("类型", item.kind))
                        .cornerRadius(4)
                }
                .chartForegroundStyleScale(domain: ["油费", "其他费用"], range: [Theme.fuel, Theme.money])
                .chartXAxis {
                    AxisMarks(values: .stride(by: .month, count: 2)) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.month(.defaultDigits))
                    }
                }
                .chartLegend(position: .bottom, alignment: .leading)
                .frame(height: 200)
            }

            Section(periodKind == .year ? "每月里程" : "最近 12 个月里程") {
                Chart(data.monthlyDistance) { item in
                    BarMark(x: .value("月份", item.month, unit: .month),
                            y: .value("km", item.value),
                            width: .ratio(0.62))
                        .foregroundStyle(LinearGradient(colors: [Theme.distance, Theme.accentSecondary],
                                                        startPoint: .bottom, endPoint: .top))
                        .cornerRadius(4)
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .month, count: 2)) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.month(.defaultDigits))
                    }
                }
                .chartYAxisLabel("km")
                .frame(height: 180)
            }

            Section("油耗趋势") {
                if data.economyPoints.isEmpty {
                    Text("这段时间没有可计算的油耗（需要两次「加满」）")
                        .foregroundStyle(.secondary)
                } else {
                    Chart(data.economyPoints) { point in
                        LineMark(x: .value("日期", point.date),
                                 y: .value("L/100km", point.value))
                            .foregroundStyle(by: .value("车辆", point.vehicleName))
                            .interpolationMethod(.monotone)
                        PointMark(x: .value("日期", point.date),
                                  y: .value("L/100km", point.value))
                            .foregroundStyle(by: .value("车辆", point.vehicleName))
                    }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .chartYAxisLabel("L/100km")
                    .frame(height: 200)
                }
            }
        }
        .appBackground()
        .animation(Theme.spring, value: periodKind)
        .animation(Theme.spring, value: anchor)
        .animation(Theme.spring, value: vehicleID)
        .navigationTitle("统计")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if !didInit {
                vehicleID = initialVehicleID
                didInit = true
            }
        }
    }

    private func shift(_ delta: Int) {
        let component: Calendar.Component = periodKind == .month ? .month : .year
        if let next = calendar.date(byAdding: component, value: delta, to: anchor) {
            anchor = min(next, Date())
        }
    }
}

struct CostSlice: Identifiable {
    let id: String
    let name: String
    let amount: Double
    let color: Color
}

struct MonthlyCost: Identifiable {
    let id = UUID()
    let month: Date
    let kind: String
    let amount: Double
}

struct MonthlyValue: Identifiable {
    let id = UUID()
    let month: Date
    let value: Double
}

struct EconomyPoint: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double
    let vehicleName: String
}

/// 统计计算
struct StatsData {
    var fuelCost: Double = 0
    var otherCost: Double = 0
    var liters: Double = 0
    var distanceKm: Double = 0
    var tripCount: Int = 0
    var averageEconomy: Double?
    var breakdown: [CostSlice] = []
    var monthlyCosts: [MonthlyCost] = []
    var monthlyDistance: [MonthlyValue] = []
    var economyPoints: [EconomyPoint] = []

    var totalCost: Double { fuelCost + otherCost }
    var costPerKm: Double? { distanceKm > 0 ? totalCost / distanceKm : nil }

    init(vehicleID: UUID?,
         interval: DateInterval,
         periodKind: StatsView.PeriodKind,
         vehicles: [Vehicle],
         trips: [Trip],
         fuel: [FuelEntry],
         expenses: [Expense],
         categories: [ExpenseCategory]) {
        let calendar = Calendar.current
        let selectedVehicles = vehicleID == nil ? vehicles : vehicles.filter { $0.id == vehicleID }
        let ids = Set(selectedVehicles.map(\.id))
        func matches(_ id: UUID?) -> Bool {
            if vehicleID == nil { return true }
            guard let id else { return false }
            return ids.contains(id)
        }
        func inPeriod(_ date: Date) -> Bool { date >= interval.start && date < interval.end }

        let periodFuel = fuel.filter { matches($0.vehicleID) && inPeriod($0.date) }
        let periodExpenses = expenses.filter { matches($0.vehicleID) && inPeriod($0.date) }
        let periodTrips = trips.filter { matches($0.vehicleID) && inPeriod($0.startDate) }

        fuelCost = periodFuel.reduce(0) { $0 + $1.totalCost }
        liters = periodFuel.reduce(0) { $0 + $1.liters }
        otherCost = periodExpenses.reduce(0) { $0 + $1.amount }
        distanceKm = periodTrips.reduce(0) { $0 + $1.distance } / 1000
        tripCount = periodTrips.count

        // 分类占比（油费算一类）
        var slices: [CostSlice] = []
        if fuelCost > 0 {
            slices.append(CostSlice(id: "fuel", name: "油费", amount: fuelCost, color: CategoryPalette.fuelColor))
        }
        var byCategory: [UUID?: Double] = [:]
        for e in periodExpenses {
            byCategory[e.categoryID, default: 0] += e.amount
        }
        for category in categories {
            if let amount = byCategory[category.id], amount > 0 {
                slices.append(CostSlice(id: category.id.uuidString, name: category.name, amount: amount,
                                        color: CategoryPalette.color(for: category)))
            }
        }
        let knownIDs = Set(categories.map(\.id))
        let uncategorized = byCategory.filter { key, _ in key == nil || !knownIDs.contains(key!) }.values.reduce(0, +)
        if uncategorized > 0 {
            slices.append(CostSlice(id: "none", name: "未分类", amount: uncategorized, color: .gray))
        }
        breakdown = slices.sorted { $0.amount > $1.amount }

        // 油耗：每辆车各自按「满箱到满箱」计算，取结束日期在周期内的段
        var periodLiters = 0.0
        var periodDistance = 0.0
        let trendStart: Date
        let trendEnd: Date
        let anchorMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: interval.start)) ?? interval.start
        if periodKind == .year {
            trendStart = interval.start
            trendEnd = interval.end
        } else {
            trendStart = calendar.date(byAdding: .month, value: -11, to: anchorMonth) ?? anchorMonth
            trendEnd = interval.end
        }
        for vehicle in selectedVehicles {
            let analysis = FuelEconomy.analyze(entries: fuel.filter { $0.vehicleID == vehicle.id })
            for segment in analysis.segments {
                if inPeriod(segment.endDate) {
                    periodLiters += segment.liters
                    periodDistance += segment.distanceKm
                }
                if segment.endDate >= trendStart && segment.endDate < trendEnd {
                    economyPoints.append(EconomyPoint(date: segment.endDate, value: segment.economy,
                                                      vehicleName: vehicle.displayName))
                }
            }
        }
        averageEconomy = periodDistance > 0 ? periodLiters / periodDistance * 100 : nil
        economyPoints.sort { $0.date < $1.date }

        // 每月花费 / 里程（12 个月）
        var months: [Date] = []
        var cursor = trendStart
        while cursor < trendEnd && months.count < 12 {
            months.append(cursor)
            guard let next = calendar.date(byAdding: .month, value: 1, to: cursor) else { break }
            cursor = next
        }
        for month in months {
            guard let end = calendar.date(byAdding: .month, value: 1, to: month) else { continue }
            let f = fuel.filter { matches($0.vehicleID) && $0.date >= month && $0.date < end }.reduce(0) { $0 + $1.totalCost }
            let o = expenses.filter { matches($0.vehicleID) && $0.date >= month && $0.date < end }.reduce(0) { $0 + $1.amount }
            let km = trips.filter { matches($0.vehicleID) && $0.startDate >= month && $0.startDate < end }.reduce(0) { $0 + $1.distance } / 1000
            monthlyCosts.append(MonthlyCost(month: month, kind: "油费", amount: f))
            monthlyCosts.append(MonthlyCost(month: month, kind: "其他费用", amount: o))
            monthlyDistance.append(MonthlyValue(month: month, value: km))
        }
    }
}
