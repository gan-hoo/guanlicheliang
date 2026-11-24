import SwiftUI
import SwiftData
import Charts
import CostKit

/// 统计：按月 / 按年 / 按车辆看每公里成本、养车成本（固定费用摊销后）、分类占比、总里程、油耗趋势。
/// 计算都在 CostKit 里（有单元测试）。
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

    /// 「本月」/「本年」
    private var periodWord: String { periodKind == .month ? "本月" : "本年" }

    private var formulaText: String {
        var lines = [
            "运行成本/km = 油费/km + 非油费运行成本/km。",
            "油费/km、平均油耗：满箱法，相邻两次加满之间的油费、油量（后一次加满 + 中间未加满）÷ 里程表差，按\(periodWord)结束的区间加权；\(periodWord)没有结束的区间时用最近一次加满。",
            "非油费运行成本/km = 近 12 个月（或车辆添加以来）运行费用 ÷ 同期行程里程。",
            "运行费用合计 = 油费 + 运行费用；养车成本（摊销后）= 运行费用合计 + 固定费用摊销（金额 ÷ 覆盖月数，从费用日期起按月计）。"
        ]
        if periodKind == .year {
            lines.append("全成本/km =（年运行费用 + 年固定费用摊销）÷ 年行程里程。")
        }
        lines.append("一次性支出（购车款、过户、改装等）不计入以上统计，在车辆页显示为「购车总投入」。")
        return lines.joined(separator: "\n")
    }

    /// 指标下的小字（没有数值时不显示）
    private func notes(_ summary: PeriodCostSummary, value: Double?, perKm: Bool, fuel: Bool) -> String? {
        guard value != nil else { return nil }
        var items: [String] = []
        if perKm && summary.isLowDistance { items.append("里程较少，仅供参考") }
        if fuel && summary.fuel?.basedOnLatest == true { items.append("基于最近一次加满") }
        return items.isEmpty ? nil : items.joined(separator: "\n")
    }

    /// 主指标：运行成本/km
    private func headline(_ summary: PeriodCostSummary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("运行成本/km")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            Text(Fmt.perKm(summary.runningCostPerKm))
                .font(.numeric(34, weight: .bold))
                .monospacedDigit()
                .contentTransition(.numericText())
            if let note = notes(summary, value: summary.runningCostPerKm, perKm: true, fuel: true) {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }

    var body: some View {
        let data = StatsData(vehicleID: vehicleID, interval: interval, periodKind: periodKind,
                             vehicles: vehicles, trips: trips, fuel: fuelEntries,
                             expenses: expenses, categories: categories)
        List {
            Group {
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

                Section {
                    headline(data.summary)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        StatTile(title: "油费/km", value: Fmt.perKm(data.summary.fuel?.costPerKm),
                                 systemImage: "fuelpump.fill", tint: Theme.fuel,
                                 note: notes(data.summary, value: data.summary.fuel?.costPerKm, perKm: true, fuel: true))
                        if periodKind == .year {
                            StatTile(title: "全成本/km", value: Fmt.perKm(data.summary.fullCostPerKm),
                                     systemImage: "sum", tint: Theme.money,
                                     note: notes(data.summary, value: data.summary.fullCostPerKm, perKm: true, fuel: false))
                        }
                        StatTile(title: "平均油耗", value: Fmt.economy(data.summary.fuel?.economy),
                                 systemImage: "gauge.with.dots.needle.33percent", tint: Theme.fuel,
                                 note: notes(data.summary, value: data.summary.fuel?.economy, perKm: false, fuel: true))
                        StatTile(title: "\(periodWord)养车成本（摊销后）", value: Fmt.money(data.summary.ownershipCost),
                                 systemImage: "creditcard.fill", tint: Theme.money)
                        StatTile(title: "运行费用合计", value: Fmt.money(data.summary.runningTotal),
                                 systemImage: "wrench.and.screwdriver.fill", tint: Theme.duration)
                        StatTile(title: "总里程", value: Fmt.km(data.summary.distanceKm),
                                 systemImage: "map.fill", tint: Theme.distance)
                        StatTile(title: "加油量", value: String(format: "%.1f L", data.summary.fuelLiters),
                                 systemImage: "drop.fill", tint: Theme.accentSecondary)
                        StatTile(title: "行程段数", value: "\(data.summary.tripCount) 段",
                                 systemImage: "car.fill", tint: Theme.altitude)
                    }
                    .padding(.vertical, 4)
                    Text("\(periodWord)一次性支出 \(Fmt.money(data.summary.oneOffInPeriod))（不计入以上统计）")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("概览")
                } footer: {
                    Text(formulaText)
                }

                Section("里程表核对") {
                    if data.odometerChecks.isEmpty {
                        Text("先添加一辆车")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(data.odometerChecks) { item in
                        OdometerCheckRow(item: item, showName: data.odometerChecks.count > 1)
                    }
                }

                Section {
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
                                Text(Fmt.money(data.breakdownTotal))
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
                                Text(String(format: "%.0f%%", item.amount / max(data.breakdownTotal, 0.0001) * 100))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 40, alignment: .trailing)
                            }
                        }
                    }
                } header: {
                    Text("花费构成")
                }

                Section(periodKind == .year ? "每月花费" : "最近 12 个月花费") {
                    Chart(data.monthlyCosts) { item in
                        BarMark(x: .value("月份", item.month, unit: .month),
                                y: .value("金额", item.amount),
                                width: .ratio(0.62))
                            .foregroundStyle(by: .value("类型", item.kind))
                            .cornerRadius(4)
                    }
                    .chartForegroundStyleScale(domain: StatsData.costKinds, range: [Theme.fuel, Theme.money, Theme.duration])
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
            .listRowBackground(Theme.rowFill)
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

/// 里程表核对的一行（每辆车一行）
struct OdometerCheckItem: Identifiable {
    let id: String
    let name: String
    let check: OdometerCheck?
}

struct OdometerCheckRow: View {
    let item: OdometerCheckItem
    let showName: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if showName {
                Text(item.name)
                    .font(.subheadline.weight(.semibold))
            }
            if let check = item.check {
                Text("\(Fmt.dateShort.string(from: check.fromDate)) → \(Fmt.dateShort.string(from: check.toDate)) 两次加油之间")
                    .font(.subheadline)
                HStack {
                    Text("里程表差 \(Fmt.km(check.odometerKm, decimals: 0))")
                    Spacer()
                    Text("行程累计 \(Fmt.km(check.tripKm, decimals: 0))")
                }
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                if check.possiblyMissingTrips {
                    Label("可能有行程漏记", systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.orange)
                }
            } else {
                Text("需要两次填了里程表的加油记录")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

/// 统计计算（数字由 CostKit 算，这里只负责取数据和组织图表）
struct StatsData {
    static let costKinds = ["油费", "其他运行费用", "固定费用摊销"]

    var summary: PeriodCostSummary
    var breakdown: [CostSlice] = []
    var monthlyCosts: [MonthlyCost] = []
    var monthlyDistance: [MonthlyValue] = []
    var economyPoints: [EconomyPoint] = []
    var odometerChecks: [OdometerCheckItem] = []

    /// 花费构成合计（= 养车成本，摊销后，不含一次性支出）
    var breakdownTotal: Double { breakdown.reduce(0) { $0 + $1.amount } }

    /// 一辆车的数据（「全部车辆」时，没有归属车辆的记录单独成一组）
    struct VehicleGroup {
        let key: UUID?
        let name: String
        let input: CostInput
    }

    init(vehicleID: UUID?,
         interval: DateInterval,
         periodKind: StatsView.PeriodKind,
         vehicles: [Vehicle],
         trips: [Trip],
         fuel: [FuelEntry],
         expenses: [Expense],
         categories: [ExpenseCategory]) {
        let calendar = Calendar.current
        let now = Date()
        let selectedVehicles = vehicleID == nil ? vehicles : vehicles.filter { $0.id == vehicleID }
        let ids = Set(selectedVehicles.map(\.id))
        func matches(_ id: UUID?) -> Bool {
            if vehicleID == nil { return true }
            guard let id else { return false }
            return ids.contains(id)
        }
        func inPeriod(_ date: Date) -> Bool { date >= interval.start && date < interval.end }

        let groups = Self.groups(vehicleID: vehicleID, vehicles: vehicles, trips: trips, fuel: fuel, expenses: expenses)
        summary = CostCalculator.summarize(groups.map(\.input), period: interval, now: now, calendar: calendar)

        // 里程表核对：每辆车单独核对
        let vehicleIDs = Set(vehicles.map(\.id))
        odometerChecks = groups.filter { $0.key.map { vehicleIDs.contains($0) } ?? false }.map { group in
            OdometerCheckItem(id: group.key?.uuidString ?? "none",
                              name: group.name,
                              check: CostCalculator.odometerCheck(fills: group.input.fills,
                                                                  trips: group.input.trips,
                                                                  in: interval))
        }

        // 花费构成：油费 + 各分类（运行费用按发生、固定费用按摊销；一次性支出不计入）
        var slices: [CostSlice] = []
        if summary.fuelSpend > 0 {
            slices.append(CostSlice(id: "fuel", name: "油费", amount: summary.fuelSpend, color: CategoryPalette.fuelColor))
        }
        var byCategory: [UUID?: Double] = [:]
        for e in expenses where matches(e.vehicleID) {
            switch e.costType {
            case .running:
                if inPeriod(e.date) { byCategory[e.categoryID, default: 0] += e.amount }
            case .fixed:
                let share = CostCalculator.amortized(item: e.costItem, in: interval, calendar: calendar)
                if share > 0 { byCategory[e.categoryID, default: 0] += share }
            case .oneOff:
                break
            }
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

        // 油耗趋势：每辆车各自按「满箱到满箱」计算
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
            for segment in analysis.segments where segment.endDate >= trendStart && segment.endDate < trendEnd {
                economyPoints.append(EconomyPoint(date: segment.endDate, value: segment.economy,
                                                  vehicleName: vehicle.displayName))
            }
        }
        economyPoints.sort { $0.date < $1.date }

        // 每月花费 / 里程（12 个月）：油费、其他运行费用按发生月份，固定费用按摊销，一次性支出不计入
        let matchedExpenses = expenses.filter { matches($0.vehicleID) }.map(\.costItem)
        var months: [Date] = []
        var cursor = trendStart
        while cursor < trendEnd && months.count < 12 {
            months.append(cursor)
            guard let next = calendar.date(byAdding: .month, value: 1, to: cursor) else { break }
            cursor = next
        }
        for month in months {
            guard let end = calendar.date(byAdding: .month, value: 1, to: month) else { continue }
            let monthInterval = DateInterval(start: month, end: end)
            let f = fuel.filter { matches($0.vehicleID) && $0.date >= month && $0.date < end }.reduce(0) { $0 + $1.totalCost }
            let running = matchedExpenses
                .filter { $0.type == .running && $0.date >= month && $0.date < end }
                .reduce(0) { $0 + $1.amount }
            let fixed = CostCalculator.amortizedFixed(matchedExpenses, in: monthInterval, calendar: calendar)
            let km = trips.filter { matches($0.vehicleID) && $0.startDate >= month && $0.startDate < end }.reduce(0) { $0 + $1.distance } / 1000
            monthlyCosts.append(MonthlyCost(month: month, kind: Self.costKinds[0], amount: f))
            monthlyCosts.append(MonthlyCost(month: month, kind: Self.costKinds[1], amount: running))
            monthlyCosts.append(MonthlyCost(month: month, kind: Self.costKinds[2], amount: fixed))
            monthlyDistance.append(MonthlyValue(month: month, value: km))
        }
    }

    /// 按车辆分组，转换成 CostKit 的输入
    static func groups(vehicleID: UUID?, vehicles: [Vehicle], trips: [Trip],
                       fuel: [FuelEntry], expenses: [Expense]) -> [VehicleGroup] {
        func make(key: UUID?, name: String, createdAt: Date?) -> VehicleGroup {
            let groupTrips = trips.filter { $0.vehicleID == key }
            let groupFuel = fuel.filter { $0.vehicleID == key }
            let groupExpenses = expenses.filter { $0.vehicleID == key }
            // 「车辆添加以来」：取车辆添加时间和第一段行程中较早的一个
            let firstTrip = groupTrips.map(\.startDate).min()
            let start = [createdAt, firstTrip].compactMap { $0 }.min()
            let input = CostInput(fills: groupFuel.map(\.fuelFill),
                                  expenses: groupExpenses.map(\.costItem),
                                  trips: groupTrips.map { TripDistance(date: $0.startDate, km: $0.distance / 1000) },
                                  trackingStart: start)
            return VehicleGroup(key: key, name: name, input: input)
        }

        if let vehicleID {
            let vehicle = vehicles.first { $0.id == vehicleID }
            return [make(key: vehicleID, name: vehicle?.displayName ?? "", createdAt: vehicle?.createdAt)]
        }
        var result = vehicles.map { make(key: $0.id, name: $0.displayName, createdAt: $0.createdAt) }
        // 没有归属车辆（或车辆已删除）的记录也算进「全部车辆」
        let known = Set(vehicles.map(\.id))
        let orphanKeys = Set(trips.map(\.vehicleID) + fuel.map(\.vehicleID) + expenses.map(\.vehicleID))
            .filter { key in key.map { !known.contains($0) } ?? true }
        for key in orphanKeys {
            result.append(make(key: key, name: "其他", createdAt: nil))
        }
        return result
    }
}
