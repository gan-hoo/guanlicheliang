import XCTest
@testable import CostKit

final class CostCalculatorTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func month(_ year: Int, _ month: Int) -> DateInterval {
        calendar.dateInterval(of: .month, for: date(year, month, 15))!
    }

    private func year(_ year: Int) -> DateInterval {
        calendar.dateInterval(of: .year, for: date(year, 6, 15))!
    }

    // MARK: 满箱法

    /// 100000→100400，30 L，$62 → 7.5 L/100km、$0.155/km
    func testFullToFullInterval() {
        let fills = [
            FuelFill(date: date(2026, 3, 1), odometer: 100_000, liters: 40, cost: 80, isFullTank: true),
            FuelFill(date: date(2026, 3, 10), odometer: 100_400, liters: 30, cost: 62, isFullTank: true)
        ]
        let intervals = CostCalculator.fuelIntervals(fills)
        XCTAssertEqual(intervals.count, 1)
        let interval = try! XCTUnwrap(intervals.first)
        XCTAssertEqual(interval.distanceKm, 400, accuracy: 1e-9)
        XCTAssertEqual(interval.liters, 30, accuracy: 1e-9)
        XCTAssertEqual(interval.economy, 7.5, accuracy: 1e-9)
        XCTAssertEqual(interval.costPerKm, 0.155, accuracy: 1e-9)

        let stats = try! XCTUnwrap(CostCalculator.fuelStats(intervals, in: month(2026, 3)))
        XCTAssertFalse(stats.basedOnLatest)
        XCTAssertEqual(stats.economy, 7.5, accuracy: 1e-9)
        XCTAssertEqual(stats.costPerKm, 0.155, accuracy: 1e-9)
    }

    /// 中间有一次未加满：油量、油费 = 后一次加满 + 中间未加满
    func testPartialFillInBetween() {
        let fills = [
            FuelFill(date: date(2026, 3, 1), odometer: 100_000, liters: 40, cost: 80, isFullTank: true),
            FuelFill(date: date(2026, 3, 5), odometer: 100_200, liters: 10, cost: 21, isFullTank: false),
            FuelFill(date: date(2026, 3, 12), odometer: 100_500, liters: 25, cost: 52, isFullTank: true)
        ]
        let intervals = CostCalculator.fuelIntervals(fills)
        XCTAssertEqual(intervals.count, 1)
        let interval = try! XCTUnwrap(intervals.first)
        XCTAssertEqual(interval.distanceKm, 500, accuracy: 1e-9)
        XCTAssertEqual(interval.liters, 35, accuracy: 1e-9)
        XCTAssertEqual(interval.cost, 73, accuracy: 1e-9)
        XCTAssertEqual(interval.economy, 7.0, accuracy: 1e-9)
        XCTAssertEqual(interval.costPerKm, 0.146, accuracy: 1e-9)
    }

    /// 输入顺序打乱也一样
    func testUnsortedInput() {
        let fills = [
            FuelFill(date: date(2026, 3, 12), odometer: 100_500, liters: 25, cost: 52, isFullTank: true),
            FuelFill(date: date(2026, 3, 1), odometer: 100_000, liters: 40, cost: 80, isFullTank: true),
            FuelFill(date: date(2026, 3, 5), odometer: 100_200, liters: 10, cost: 21, isFullTank: false)
        ]
        let interval = try! XCTUnwrap(CostCalculator.fuelIntervals(fills).first)
        XCTAssertEqual(interval.liters, 35, accuracy: 1e-9)
    }

    /// 只有一次加满 → 没有区间 → 显示「—」
    func testSingleFullFillShowsDash() {
        let fills = [
            FuelFill(date: date(2026, 3, 1), odometer: 100_000, liters: 40, cost: 80, isFullTank: true),
            FuelFill(date: date(2026, 3, 8), odometer: 100_300, liters: 15, cost: 31, isFullTank: false)
        ]
        let intervals = CostCalculator.fuelIntervals(fills)
        XCTAssertTrue(intervals.isEmpty)
        let stats = CostCalculator.fuelStats(intervals, in: month(2026, 3))
        XCTAssertNil(stats)
        XCTAssertEqual(CostCalculator.display(stats?.economy) { String(format: "%.1f", $0) }, "—")
        XCTAssertEqual(CostCalculator.display(stats?.costPerKm) { String(format: "%.3f", $0) }, "—")
    }

    /// 「上次漏记」或缺里程表的区间不算
    func testMissedPreviousAndMissingOdometerSkipInterval() {
        let missed = [
            FuelFill(date: date(2026, 3, 1), odometer: 100_000, liters: 40, cost: 80),
            FuelFill(date: date(2026, 3, 10), odometer: 100_400, liters: 30, cost: 62, missedPrevious: true)
        ]
        XCTAssertTrue(CostCalculator.fuelIntervals(missed).isEmpty)

        let noOdometer = [
            FuelFill(date: date(2026, 3, 1), odometer: 0, liters: 40, cost: 80),
            FuelFill(date: date(2026, 3, 10), odometer: 100_400, liters: 30, cost: 62)
        ]
        XCTAssertTrue(CostCalculator.fuelIntervals(noOdometer).isEmpty)
    }

    /// 月视图：当月结束的多个区间按里程加权
    func testMonthlyStatsWeightedByDistance() {
        let fills = [
            FuelFill(date: date(2026, 3, 1), odometer: 100_000, liters: 40, cost: 80),
            FuelFill(date: date(2026, 3, 10), odometer: 100_400, liters: 30, cost: 60),   // 7.5
            FuelFill(date: date(2026, 3, 20), odometer: 100_500, liters: 10, cost: 20)    // 10.0
        ]
        let intervals = CostCalculator.fuelIntervals(fills)
        XCTAssertEqual(intervals.count, 2)
        let stats = try! XCTUnwrap(CostCalculator.fuelStats(intervals, in: month(2026, 3)))
        XCTAssertEqual(stats.intervalCount, 2)
        // (30 + 10) ÷ 500 × 100 = 8.0，不是 (7.5 + 10) ÷ 2
        XCTAssertEqual(stats.economy, 8.0, accuracy: 1e-9)
        XCTAssertEqual(stats.costPerKm, 0.16, accuracy: 1e-9)
    }

    /// 当月没有结束的区间 → 用最近一个区间并标记
    func testMonthWithoutIntervalUsesLatest() {
        let fills = [
            FuelFill(date: date(2026, 1, 5), odometer: 100_000, liters: 40, cost: 80),
            FuelFill(date: date(2026, 1, 20), odometer: 100_400, liters: 30, cost: 62),
            FuelFill(date: date(2026, 2, 10), odometer: 100_900, liters: 40, cost: 90)
        ]
        let intervals = CostCalculator.fuelIntervals(fills)
        let stats = try! XCTUnwrap(CostCalculator.fuelStats(intervals, in: month(2026, 4)))
        XCTAssertTrue(stats.basedOnLatest)
        XCTAssertEqual(stats.distanceKm, 500, accuracy: 1e-9)
        XCTAssertEqual(stats.economy, 8.0, accuracy: 1e-9)
    }

    // MARK: 固定费用摊销

    /// rego $900 覆盖 12 个月 → 每月 $75
    func testRegoAmortization() {
        let rego = CostItem(date: date(2026, 3, 15), amount: 900, type: .fixed, coverageMonths: 12)
        XCTAssertEqual(CostCalculator.monthlyShare(of: rego), 75, accuracy: 1e-9)
        XCTAssertEqual(CostCalculator.amortizedFixed([rego], in: month(2026, 3), calendar: calendar), 75, accuracy: 1e-9)
        XCTAssertEqual(CostCalculator.amortizedFixed([rego], in: month(2026, 12), calendar: calendar), 75, accuracy: 1e-9)
        XCTAssertEqual(CostCalculator.amortizedFixed([rego], in: month(2027, 2), calendar: calendar), 75, accuracy: 1e-9)
        // 从费用日期所在月份开始，覆盖 12 个月之外为 0
        XCTAssertEqual(CostCalculator.amortizedFixed([rego], in: month(2026, 2), calendar: calendar), 0, accuracy: 1e-9)
        XCTAssertEqual(CostCalculator.amortizedFixed([rego], in: month(2027, 3), calendar: calendar), 0, accuracy: 1e-9)
        // 年视图：2026 年 3–12 月 10 个月，2027 年 1–2 月 2 个月
        XCTAssertEqual(CostCalculator.amortizedFixed([rego], in: year(2026), calendar: calendar), 750, accuracy: 1e-9)
        XCTAssertEqual(CostCalculator.amortizedFixed([rego], in: year(2027), calendar: calendar), 150, accuracy: 1e-9)
    }

    func testOnlyFixedItemsAreAmortized() {
        let items = [
            CostItem(date: date(2026, 3, 15), amount: 900, type: .fixed, coverageMonths: 12),
            CostItem(date: date(2026, 3, 15), amount: 300, type: .running),
            CostItem(date: date(2026, 3, 15), amount: 30_000, type: .oneOff)
        ]
        XCTAssertEqual(CostCalculator.amortizedFixed(items, in: month(2026, 3), calendar: calendar), 75, accuracy: 1e-9)
    }

    // MARK: 一次性支出

    /// 一次性支出不影响月/年统计，只计入 oneOffInPeriod 和购车总投入
    func testOneOffDoesNotAffectPeriodStats() {
        let fills = [
            FuelFill(date: date(2026, 3, 1), odometer: 100_000, liters: 40, cost: 80),
            FuelFill(date: date(2026, 3, 10), odometer: 100_400, liters: 30, cost: 62)
        ]
        let trips = [
            TripDistance(date: date(2026, 3, 3), km: 150),
            TripDistance(date: date(2026, 3, 7), km: 250)
        ]
        let base = [
            CostItem(date: date(2026, 3, 5), amount: 120, type: .running),
            CostItem(date: date(2026, 3, 15), amount: 900, type: .fixed, coverageMonths: 12)
        ]
        let purchase = CostItem(date: date(2026, 3, 2), amount: 30_000, type: .oneOff)
        let now = date(2026, 12, 31)

        for period in [month(2026, 3), year(2026)] {
            let without = CostCalculator.summarize(CostInput(fills: fills, expenses: base, trips: trips),
                                                   period: period, now: now, calendar: calendar)
            let with = CostCalculator.summarize(CostInput(fills: fills, expenses: base + [purchase], trips: trips),
                                                period: period, now: now, calendar: calendar)
            XCTAssertEqual(without.oneOffInPeriod, 0)
            XCTAssertEqual(with.oneOffInPeriod, 30_000, accuracy: 1e-9)

            XCTAssertEqual(with.runningTotal, without.runningTotal, accuracy: 1e-9)
            XCTAssertEqual(with.fixedAmortized, without.fixedAmortized, accuracy: 1e-9)
            XCTAssertEqual(with.ownershipCost, without.ownershipCost, accuracy: 1e-9)
            XCTAssertEqual(with.runningCostPerKm!, without.runningCostPerKm!, accuracy: 1e-9)
            XCTAssertEqual(with.nonFuelRunningPerKm!, without.nonFuelRunningPerKm!, accuracy: 1e-9)
            XCTAssertEqual(with.fullCostPerKm!, without.fullCostPerKm!, accuracy: 1e-9)
            XCTAssertEqual(with.distanceKm, without.distanceKm, accuracy: 1e-9)
        }
        XCTAssertEqual(CostCalculator.oneOffTotal(base + [purchase]), 30_000, accuracy: 1e-9)
    }

    // MARK: 每公里成本

    func testSummaryPerKmMetrics() {
        let fills = [
            FuelFill(date: date(2026, 3, 1), odometer: 100_000, liters: 40, cost: 80),
            FuelFill(date: date(2026, 3, 10), odometer: 100_400, liters: 30, cost: 62)
        ]
        let trips = [TripDistance(date: date(2026, 3, 3), km: 400)]
        let expenses = [
            CostItem(date: date(2026, 3, 5), amount: 40, type: .running),
            CostItem(date: date(2026, 3, 15), amount: 900, type: .fixed, coverageMonths: 12)
        ]
        let summary = CostCalculator.summarize(CostInput(fills: fills, expenses: expenses, trips: trips,
                                                         trackingStart: date(2026, 3, 1, 0)),
                                               period: month(2026, 3), now: date(2026, 3, 31), calendar: calendar)
        XCTAssertEqual(summary.fuel!.costPerKm, 0.155, accuracy: 1e-9)
        XCTAssertEqual(summary.nonFuelRunningPerKm!, 0.1, accuracy: 1e-9)       // 40 ÷ 400
        XCTAssertEqual(summary.runningCostPerKm!, 0.255, accuracy: 1e-9)        // 0.155 + 0.1
        XCTAssertEqual(summary.fuelSpend, 142, accuracy: 1e-9)                  // 80 + 62
        XCTAssertEqual(summary.runningTotal, 182, accuracy: 1e-9)               // 142 + 40
        XCTAssertEqual(summary.fixedAmortized, 75, accuracy: 1e-9)
        XCTAssertEqual(summary.ownershipCost, 257, accuracy: 1e-9)
        XCTAssertEqual(summary.fullCostPerKm!, 257.0 / 400.0, accuracy: 1e-9)
        XCTAssertEqual(summary.tripCount, 1)
        XCTAssertFalse(summary.isLowDistance)
    }

    func testLowDistanceAndNoTrips() {
        let summary = CostCalculator.summarize(CostInput(fills: [], expenses: [], trips: [TripDistance(date: date(2026, 3, 3), km: 120)]),
                                               period: month(2026, 3), now: date(2026, 3, 31), calendar: calendar)
        XCTAssertTrue(summary.isLowDistance)
        XCTAssertNil(summary.fuel)
        XCTAssertNil(summary.runningCostPerKm)

        let empty = CostCalculator.summarize(CostInput(fills: [], expenses: [], trips: []),
                                             period: month(2026, 3), now: date(2026, 3, 31), calendar: calendar)
        XCTAssertNil(empty.nonFuelRunningPerKm)
        XCTAssertNil(empty.fullCostPerKm)
    }

    /// 近 12 个月窗口：不早于车辆添加时间
    func testRunningWindow() {
        let end = date(2026, 6, 30)
        let full = CostCalculator.runningWindow(endingAt: end, notBefore: nil, calendar: calendar)
        XCTAssertEqual(full.start, date(2025, 6, 30))
        let since = CostCalculator.runningWindow(endingAt: end, notBefore: date(2026, 2, 1), calendar: calendar)
        XCTAssertEqual(since.start, date(2026, 2, 1))

        let expenses = [
            CostItem(date: date(2025, 1, 10), amount: 1_000, type: .running),  // 窗口外
            CostItem(date: date(2026, 3, 10), amount: 200, type: .running),
            CostItem(date: date(2026, 3, 10), amount: 900, type: .fixed),
            CostItem(date: date(2026, 3, 10), amount: 5_000, type: .oneOff)
        ]
        let trips = [TripDistance(date: date(2026, 4, 1), km: 1_000)]
        XCTAssertEqual(CostCalculator.nonFuelRunningPerKm(expenses: expenses, trips: trips, window: full)!, 0.2, accuracy: 1e-9)
    }

    // MARK: 里程表核对

    func testOdometerCheck() {
        let fills = [
            FuelFill(date: date(2026, 3, 1), odometer: 100_000, liters: 40, cost: 80),
            FuelFill(date: date(2026, 3, 20), odometer: 100_500, liters: 30, cost: 62)
        ]
        let missing = CostCalculator.odometerCheck(fills: fills, trips: [TripDistance(date: date(2026, 3, 5), km: 400)],
                                                   in: month(2026, 3))
        XCTAssertEqual(missing!.odometerKm, 500, accuracy: 1e-9)
        XCTAssertEqual(missing!.tripKm, 400, accuracy: 1e-9)
        XCTAssertTrue(missing!.possiblyMissingTrips)       // 差 20%

        let ok = CostCalculator.odometerCheck(fills: fills, trips: [TripDistance(date: date(2026, 3, 5), km: 470)],
                                              in: month(2026, 3))
        XCTAssertFalse(ok!.possiblyMissingTrips)           // 差 6%

        XCTAssertNil(CostCalculator.odometerCheck(fills: [fills[0]], trips: [], in: month(2026, 3)))
    }

    /// 多辆车：油耗按车各自算区间再相加，不会把两辆车的里程表混在一起
    func testMultipleVehiclesSummary() {
        let carA = CostInput(fills: [
            FuelFill(date: date(2026, 3, 1), odometer: 100_000, liters: 40, cost: 80),
            FuelFill(date: date(2026, 3, 10), odometer: 100_400, liters: 30, cost: 60)
        ], expenses: [CostItem(date: date(2026, 3, 5), amount: 100, type: .running)],
           trips: [TripDistance(date: date(2026, 3, 3), km: 400)])
        let carB = CostInput(fills: [
            FuelFill(date: date(2026, 3, 2), odometer: 20_000, liters: 50, cost: 100),
            FuelFill(date: date(2026, 3, 12), odometer: 20_600, liters: 60, cost: 120)
        ], expenses: [CostItem(date: date(2026, 3, 5), amount: 9_000, type: .oneOff)],
           trips: [TripDistance(date: date(2026, 3, 4), km: 600)])
        let summary = CostCalculator.summarize([carA, carB], period: month(2026, 3),
                                               now: date(2026, 3, 31), calendar: calendar)
        XCTAssertEqual(summary.fuel!.distanceKm, 1_000, accuracy: 1e-9)
        XCTAssertEqual(summary.fuel!.economy, 9.0, accuracy: 1e-9)          // (30 + 60) ÷ 1000 × 100
        XCTAssertEqual(summary.fuel!.costPerKm, 0.18, accuracy: 1e-9)       // (60 + 120) ÷ 1000
        XCTAssertEqual(summary.nonFuelRunningPerKm!, 0.1, accuracy: 1e-9)   // 100 ÷ 1000
        XCTAssertEqual(summary.runningCostPerKm!, 0.28, accuracy: 1e-9)
        XCTAssertEqual(summary.distanceKm, 1_000, accuracy: 1e-9)
        XCTAssertEqual(summary.oneOffInPeriod, 9_000, accuracy: 1e-9)
        XCTAssertEqual(summary.runningTotal, 460, accuracy: 1e-9)           // 80+60+100+120 + 100
    }

    // MARK: 分类 → 类型

    func testSuggestedCostType() {
        XCTAssertEqual(CostType.suggested(forCategoryName: "保养"), .running)
        XCTAssertEqual(CostType.suggested(forCategoryName: "维修"), .running)
        XCTAssertEqual(CostType.suggested(forCategoryName: "轮胎"), .running)
        XCTAssertEqual(CostType.suggested(forCategoryName: "过路费"), .running)
        XCTAssertEqual(CostType.suggested(forCategoryName: "停车"), .running)
        XCTAssertEqual(CostType.suggested(forCategoryName: "注册费 / rego"), .fixed)
        XCTAssertEqual(CostType.suggested(forCategoryName: "CTP"), .fixed)
        XCTAssertEqual(CostType.suggested(forCategoryName: "保险"), .fixed)
        XCTAssertEqual(CostType.suggested(forCategoryName: "道路救援"), .fixed)
        XCTAssertEqual(CostType.suggested(forCategoryName: "洗车"), .fixed)
        XCTAssertEqual(CostType.suggested(forCategoryName: "购车款"), .oneOff)
        XCTAssertEqual(CostType.suggested(forCategoryName: "过户/印花税"), .oneOff)
        XCTAssertEqual(CostType.suggested(forCategoryName: "配件 / 改装"), .oneOff)
        XCTAssertEqual(CostType.suggested(forCategoryName: "年检"), .running)
        XCTAssertEqual(CostType.suggested(forCategoryName: "其他"), .running)
        XCTAssertEqual(CostType.suggested(forCategoryName: nil), .running)
    }
}
