import Foundation

// MARK: - 费用类型

/// 费用类型：决定一笔费用怎样进入统计
public enum CostType: String, CaseIterable, Codable, Sendable {
    /// 运行费用：按发生月份计入，参与「每公里运行成本」
    case running
    /// 固定费用：按覆盖月数逐月摊销（rego、保险等）
    case fixed
    /// 一次性支出：不进入任何月/年统计，单独显示为「购车总投入」
    case oneOff

    public var displayName: String {
        switch self {
        case .running: return "运行费用"
        case .fixed: return "固定费用"
        case .oneOff: return "一次性支出"
        }
    }

    /// 按分类名称推荐的类型；匹配不到的一律算运行费用
    public static func suggested(forCategoryName name: String?) -> CostType {
        let text = (name ?? "").lowercased()
        if text.isEmpty { return .running }
        let oneOffKeys = ["购车", "过户", "印花", "改装", "配件"]
        let fixedKeys = ["rego", "注册", "ctp", "保险", "救援", "洗车", "美容"]
        if oneOffKeys.contains(where: { text.contains($0) }) { return .oneOff }
        if fixedKeys.contains(where: { text.contains($0) }) { return .fixed }
        return .running
    }

    /// 固定费用默认摊销月数
    public static let defaultCoverageMonths = 12
}

// MARK: - 输入数据

/// 一次加油
public struct FuelFill: Sendable, Hashable {
    public var id: UUID
    public var date: Date
    /// 里程表读数；nil 或 ≤ 0 表示没填
    public var odometer: Double?
    public var liters: Double
    public var cost: Double
    public var isFullTank: Bool
    /// 这次之前有漏记的加油（这次结束的区间不可信）
    public var missedPrevious: Bool

    public init(id: UUID = UUID(), date: Date, odometer: Double?, liters: Double, cost: Double,
                isFullTank: Bool = true, missedPrevious: Bool = false) {
        self.id = id
        self.date = date
        self.odometer = odometer
        self.liters = liters
        self.cost = cost
        self.isFullTank = isFullTank
        self.missedPrevious = missedPrevious
    }

    var validOdometer: Double? {
        guard let odometer, odometer > 0 else { return nil }
        return odometer
    }
}

/// 一笔费用（加油以外）
public struct CostItem: Sendable, Hashable {
    public var date: Date
    public var amount: Double
    public var type: CostType
    /// 固定费用的覆盖月数（其他类型忽略）
    public var coverageMonths: Int

    public init(date: Date, amount: Double, type: CostType, coverageMonths: Int = CostType.defaultCoverageMonths) {
        self.date = date
        self.amount = amount
        self.type = type
        self.coverageMonths = coverageMonths
    }
}

/// 一段行程的里程
public struct TripDistance: Sendable, Hashable {
    public var date: Date
    public var km: Double

    public init(date: Date, km: Double) {
        self.date = date
        self.km = km
    }
}

// MARK: - 结果

/// 满箱法的一个区间：相邻两次加满之间
public struct FuelInterval: Sendable, Hashable, Identifiable {
    public var id: UUID { endFillID }
    public var startFillID: UUID
    public var endFillID: UUID
    public var startDate: Date
    public var endDate: Date
    public var distanceKm: Double
    /// 后一次加满 + 中间所有未加满的油量
    public var liters: Double
    /// 后一次加满 + 中间所有未加满的油费
    public var cost: Double

    /// L/100km
    public var economy: Double { liters / distanceKm * 100 }
    /// 油费/km
    public var costPerKm: Double { cost / distanceKm }
}

/// 某段时间的油耗（按区间加权）
public struct FuelStats: Sendable, Hashable {
    public var distanceKm: Double
    public var liters: Double
    public var cost: Double
    public var intervalCount: Int
    /// 这段时间没有结束的区间，用的是最近一个区间（显示「基于最近一次加满」）
    public var basedOnLatest: Bool

    /// L/100km
    public var economy: Double { liters / distanceKm * 100 }
    /// 油费/km
    public var costPerKm: Double { cost / distanceKm }
}

/// 里程表核对：两次加油的里程表差 vs 期间行程累计
public struct OdometerCheck: Sendable, Hashable {
    public var fromDate: Date
    public var toDate: Date
    public var odometerKm: Double
    public var tripKm: Double

    /// 行程比里程表少的比例（负数表示行程更多）
    public var gapRatio: Double { (odometerKm - tripKm) / odometerKm }
    /// 差超过 10%：可能有行程漏记
    public var possiblyMissingTrips: Bool { gapRatio > CostCalculator.odometerGapThreshold }
}

/// 一个月或一年的成本汇总
public struct PeriodCostSummary: Sendable, Hashable {
    public var period: DateInterval
    /// 行程里程
    public var distanceKm: Double
    public var tripCount: Int
    /// 这段时间加的油（按加油日期）
    public var fuelLiters: Double
    public var fuelSpend: Double
    /// 运行类费用（不含油费）
    public var runningExpenses: Double
    /// 固定费用在这段时间的摊销
    public var fixedAmortized: Double
    /// 这段时间的一次性支出（不计入任何统计，只单独显示）
    public var oneOffInPeriod: Double
    /// 满箱法油耗与油费/km
    public var fuel: FuelStats?
    /// 非油费运行成本/km（近 12 个月或车辆添加以来）
    public var nonFuelRunningPerKm: Double?
    /// 运行成本/km = 油费/km + 非油费运行成本/km
    public var runningCostPerKm: Double?
    /// 全成本/km = (运行费用合计 + 固定摊销) ÷ 里程（年视图显示）
    public var fullCostPerKm: Double?
    public var odometerCheck: OdometerCheck?

    /// 运行费用合计 = 油费 + 运行类费用
    public var runningTotal: Double { fuelSpend + runningExpenses }
    /// 养车成本（摊销后）= 运行费用合计 + 固定摊销；不含一次性支出
    public var ownershipCost: Double { runningTotal + fixedAmortized }
    /// 里程少于 300 km，每公里指标仅供参考
    public var isLowDistance: Bool { distanceKm < CostCalculator.lowDistanceThreshold }
}

/// summarize 的输入（一辆车的全部数据）
public struct CostInput: Sendable {
    public var fills: [FuelFill]
    public var expenses: [CostItem]
    public var trips: [TripDistance]
    /// 车辆添加时间；近 12 个月窗口不早于这个时间
    public var trackingStart: Date?

    public init(fills: [FuelFill], expenses: [CostItem], trips: [TripDistance], trackingStart: Date? = nil) {
        self.fills = fills
        self.expenses = expenses
        self.trips = trips
        self.trackingStart = trackingStart
    }
}

// MARK: - 计算

public enum CostCalculator {
    public static let lowDistanceThreshold: Double = 300
    public static let odometerGapThreshold: Double = 0.10
    public static let runningWindowMonths = 12

    /// 满箱法区间。
    /// 区间 = 相邻两次加满；油量、油费 = 后一次加满 + 中间所有未加满；里程 = 里程表差。
    /// 区间内有「上次漏记」、缺里程表、里程不增加或油耗明显不合理（≤0.5 或 ≥100 L/100km）的不算。
    public static func fuelIntervals(_ fills: [FuelFill]) -> [FuelInterval] {
        let sorted = fills.sorted {
            if $0.date != $1.date { return $0.date < $1.date }
            return ($0.odometer ?? 0) < ($1.odometer ?? 0)
        }
        var result: [FuelInterval] = []
        var lastFull: FuelFill?
        var liters = 0.0
        var cost = 0.0
        var broken = false

        for fill in sorted {
            guard let start = lastFull else {
                if fill.isFullTank { lastFull = fill }
                continue
            }
            liters += fill.liters
            cost += fill.cost
            if fill.missedPrevious { broken = true }
            guard fill.isFullTank else { continue }

            if !broken,
               let from = start.validOdometer,
               let to = fill.validOdometer,
               to > from,
               liters > 0 {
                let interval = FuelInterval(startFillID: start.id, endFillID: fill.id,
                                            startDate: start.date, endDate: fill.date,
                                            distanceKm: to - from, liters: liters, cost: cost)
                if interval.economy > 0.5 && interval.economy < 100 {
                    result.append(interval)
                }
            }
            lastFull = fill
            liters = 0
            cost = 0
            broken = false
        }
        return result
    }

    /// 某段时间的油耗：取结束在这段时间内的区间，按里程加权（总油量 ÷ 总里程）。
    /// 没有这样的区间时，取这段时间结束前最近的一个区间并标记 basedOnLatest；
    /// 一个区间都没有时返回 nil（显示「—」）。
    public static func fuelStats(_ intervals: [FuelInterval], in period: DateInterval) -> FuelStats? {
        guard !intervals.isEmpty else { return nil }
        let inside = intervals.filter { $0.endDate >= period.start && $0.endDate < period.end }
        if !inside.isEmpty {
            return FuelStats(distanceKm: inside.reduce(0) { $0 + $1.distanceKm },
                             liters: inside.reduce(0) { $0 + $1.liters },
                             cost: inside.reduce(0) { $0 + $1.cost },
                             intervalCount: inside.count,
                             basedOnLatest: false)
        }
        let before = intervals.filter { $0.endDate < period.end }
        let latest = before.max(by: { $0.endDate < $1.endDate })
            ?? intervals.min(by: { $0.endDate < $1.endDate })
        guard let latest else { return nil }
        return FuelStats(distanceKm: latest.distanceKm, liters: latest.liters, cost: latest.cost,
                         intervalCount: 1, basedOnLatest: true)
    }

    /// 一笔固定费用每月摊销的金额
    public static func monthlyShare(of item: CostItem) -> Double {
        item.amount / Double(max(1, item.coverageMonths))
    }

    /// 固定费用在某段时间的摊销：每月 = 金额 ÷ 覆盖月数，从费用日期所在月份开始。
    /// 月视图传当月，年视图传当年。
    public static func amortizedFixed(_ items: [CostItem], in period: DateInterval, calendar: Calendar) -> Double {
        items.reduce(0) { $0 + amortized(item: $1, in: period, calendar: calendar) }
    }

    /// 单笔固定费用在某段时间的摊销（不是固定费用返回 0）
    public static func amortized(item: CostItem, in period: DateInterval, calendar: Calendar) -> Double {
        guard item.type == .fixed else { return 0 }
        let months = max(1, item.coverageMonths)
        guard let firstMonth = calendar.dateInterval(of: .month, for: item.date)?.start else { return 0 }
        let share = item.amount / Double(months)
        var total = 0.0
        for offset in 0..<months {
            guard let monthStart = calendar.date(byAdding: .month, value: offset, to: firstMonth) else { continue }
            if monthStart >= period.end { break }
            if monthStart >= period.start { total += share }
        }
        return total
    }

    /// 一次性支出合计（所有日期）
    public static func oneOffTotal(_ items: [CostItem]) -> Double {
        items.filter { $0.type == .oneOff }.reduce(0) { $0 + $1.amount }
    }

    /// 计算「非油费运行成本/km」用的时间窗：截至 end 的近 12 个月，但不早于车辆添加时间
    public static func runningWindow(endingAt end: Date, notBefore start: Date?, calendar: Calendar) -> DateInterval {
        var from = calendar.date(byAdding: .month, value: -runningWindowMonths, to: end) ?? end
        if let start, start > from { from = min(start, end) }
        return DateInterval(start: from, end: end)
    }

    /// 时间窗内的运行类费用（不含油费）和行程里程
    public static func runningSpendAndDistance(expenses: [CostItem], trips: [TripDistance],
                                               window: DateInterval) -> (spend: Double, km: Double) {
        let km = trips.filter { $0.date >= window.start && $0.date < window.end }.reduce(0) { $0 + $1.km }
        let spend = expenses
            .filter { $0.type == .running && $0.date >= window.start && $0.date < window.end }
            .reduce(0) { $0 + $1.amount }
        return (spend, km)
    }

    /// 非油费运行成本/km = 时间窗内运行类费用 ÷ 时间窗内行程里程；没有里程返回 nil
    public static func nonFuelRunningPerKm(expenses: [CostItem], trips: [TripDistance], window: DateInterval) -> Double? {
        let total = runningSpendAndDistance(expenses: expenses, trips: trips, window: window)
        guard total.km > 0 else { return nil }
        return total.spend / total.km
    }

    /// 运行成本/km = 油费/km + 非油费运行成本/km（任一缺失返回 nil）
    public static func runningCostPerKm(fuelPerKm: Double?, nonFuelPerKm: Double?) -> Double? {
        guard let fuelPerKm, let nonFuelPerKm else { return nil }
        return fuelPerKm + nonFuelPerKm
    }

    /// 全成本/km = (运行费用合计 + 固定摊销) ÷ 里程；没有里程返回 nil
    public static func fullCostPerKm(runningTotal: Double, fixedAmortized: Double, distanceKm: Double) -> Double? {
        guard distanceKm > 0 else { return nil }
        return (runningTotal + fixedAmortized) / distanceKm
    }

    /// 里程表核对：取这段时间内第一次和最后一次有里程表的加油；
    /// 不足两次时取这段时间结束前最近的两次。比较里程表差和这期间的行程累计。
    public static func odometerCheck(fills: [FuelFill], trips: [TripDistance], in period: DateInterval) -> OdometerCheck? {
        let withOdometer = fills
            .filter { $0.validOdometer != nil }
            .sorted { $0.date < $1.date }
        let inside = withOdometer.filter { $0.date >= period.start && $0.date < period.end }
        let pair: (FuelFill, FuelFill)
        if inside.count >= 2, let first = inside.first, let last = inside.last {
            pair = (first, last)
        } else {
            let before = withOdometer.filter { $0.date < period.end }
            guard before.count >= 2 else { return nil }
            pair = (before[before.count - 2], before[before.count - 1])
        }
        guard let from = pair.0.validOdometer, let to = pair.1.validOdometer, to > from else { return nil }
        let tripKm = trips
            .filter { $0.date >= pair.0.date && $0.date < pair.1.date }
            .reduce(0) { $0 + $1.km }
        return OdometerCheck(fromDate: pair.0.date, toDate: pair.1.date, odometerKm: to - from, tripKm: tripKm)
    }

    /// 汇总一个月或一年。一次性支出只记在 oneOffInPeriod，不进入其他任何数字。
    /// now 用来限定「近 12 个月」窗口不超过今天。
    public static func summarize(_ input: CostInput, period: DateInterval, now: Date = Date(), calendar: Calendar) -> PeriodCostSummary {
        func inPeriod(_ date: Date) -> Bool { date >= period.start && date < period.end }

        let periodTrips = input.trips.filter { inPeriod($0.date) }
        let distance = periodTrips.reduce(0) { $0 + $1.km }
        let periodFills = input.fills.filter { inPeriod($0.date) }
        let fuelSpend = periodFills.reduce(0) { $0 + $1.cost }
        let fuelLiters = periodFills.reduce(0) { $0 + $1.liters }
        let runningExpenses = input.expenses
            .filter { $0.type == .running && inPeriod($0.date) }
            .reduce(0) { $0 + $1.amount }
        let fixed = amortizedFixed(input.expenses, in: period, calendar: calendar)
        let oneOff = input.expenses
            .filter { $0.type == .oneOff && inPeriod($0.date) }
            .reduce(0) { $0 + $1.amount }

        let fuel = fuelStats(fuelIntervals(input.fills), in: period)
        let window = runningWindow(endingAt: min(period.end, now), notBefore: input.trackingStart, calendar: calendar)
        let nonFuel = nonFuelRunningPerKm(expenses: input.expenses, trips: input.trips, window: window)
        let running = runningCostPerKm(fuelPerKm: fuel?.costPerKm, nonFuelPerKm: nonFuel)
        let full = fullCostPerKm(runningTotal: fuelSpend + runningExpenses, fixedAmortized: fixed, distanceKm: distance)

        return PeriodCostSummary(period: period,
                                 distanceKm: distance,
                                 tripCount: periodTrips.count,
                                 fuelLiters: fuelLiters,
                                 fuelSpend: fuelSpend,
                                 runningExpenses: runningExpenses,
                                 fixedAmortized: fixed,
                                 oneOffInPeriod: oneOff,
                                 fuel: fuel,
                                 nonFuelRunningPerKm: nonFuel,
                                 runningCostPerKm: running,
                                 fullCostPerKm: full,
                                 odometerCheck: odometerCheck(fills: input.fills, trips: input.trips, in: period))
    }

    /// 多辆车合计：油耗区间按车各自计算，再把油量、里程、金额相加。
    /// 只有一辆车时等同于 summarize(_:period:)；多辆车时不做里程表核对（各车单独核对）。
    public static func summarize(_ inputs: [CostInput], period: DateInterval, now: Date = Date(), calendar: Calendar) -> PeriodCostSummary {
        if inputs.count == 1 {
            return summarize(inputs[0], period: period, now: now, calendar: calendar)
        }
        let parts = inputs.map { summarize($0, period: period, now: now, calendar: calendar) }

        var fuel: FuelStats?
        for stats in parts.compactMap(\.fuel) {
            if var merged = fuel {
                merged.distanceKm += stats.distanceKm
                merged.liters += stats.liters
                merged.cost += stats.cost
                merged.intervalCount += stats.intervalCount
                merged.basedOnLatest = merged.basedOnLatest || stats.basedOnLatest
                fuel = merged
            } else {
                fuel = stats
            }
        }

        var spend = 0.0
        var km = 0.0
        for input in inputs {
            let window = runningWindow(endingAt: min(period.end, now), notBefore: input.trackingStart, calendar: calendar)
            let total = runningSpendAndDistance(expenses: input.expenses, trips: input.trips, window: window)
            spend += total.spend
            km += total.km
        }
        let nonFuel: Double? = km > 0 ? spend / km : nil

        let distance = parts.reduce(0) { $0 + $1.distanceKm }
        let fuelSpend = parts.reduce(0) { $0 + $1.fuelSpend }
        let runningExpenses = parts.reduce(0) { $0 + $1.runningExpenses }
        let fixed = parts.reduce(0) { $0 + $1.fixedAmortized }

        return PeriodCostSummary(period: period,
                                 distanceKm: distance,
                                 tripCount: parts.reduce(0) { $0 + $1.tripCount },
                                 fuelLiters: parts.reduce(0) { $0 + $1.fuelLiters },
                                 fuelSpend: fuelSpend,
                                 runningExpenses: runningExpenses,
                                 fixedAmortized: fixed,
                                 oneOffInPeriod: parts.reduce(0) { $0 + $1.oneOffInPeriod },
                                 fuel: fuel,
                                 nonFuelRunningPerKm: nonFuel,
                                 runningCostPerKm: runningCostPerKm(fuelPerKm: fuel?.costPerKm, nonFuelPerKm: nonFuel),
                                 fullCostPerKm: fullCostPerKm(runningTotal: fuelSpend + runningExpenses,
                                                              fixedAmortized: fixed, distanceKm: distance),
                                 odometerCheck: nil)
    }

    /// 显示用：nil 显示「—」
    public static func display(_ value: Double?, _ format: (Double) -> String) -> String {
        guard let value, value.isFinite else { return "—" }
        return format(value)
    }
}
