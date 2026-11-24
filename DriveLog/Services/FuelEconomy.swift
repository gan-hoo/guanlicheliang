import Foundation
import CostKit

/// 一段「满箱到满箱」
struct FuelSegment: Identifiable {
    /// 结束这段的那次加满记录的 ID
    let id: UUID
    let startDate: Date
    let endDate: Date
    let distanceKm: Double
    let liters: Double
    let cost: Double

    var economy: Double { liters / distanceKm * 100 }
}

struct FuelAnalysis {
    let segments: [FuelSegment]
    /// 每次加满记录对应的油耗（L/100km）
    let economyByEntryID: [UUID: Double]

    var totalLiters: Double { segments.reduce(0) { $0 + $1.liters } }
    var totalDistanceKm: Double { segments.reduce(0) { $0 + $1.distanceKm } }
    var totalCost: Double { segments.reduce(0) { $0 + $1.cost } }

    /// 平均油耗：有效段总油量 ÷ 有效段总里程
    var averageEconomy: Double? {
        let d = totalDistanceKm
        return d > 0 ? totalLiters / d * 100 : nil
    }

    /// 每公里油费
    var costPerKm: Double? {
        let d = totalDistanceKm
        return d > 0 ? totalCost / d : nil
    }
}

/// 油耗用「满箱到满箱」法（计算在 CostKit 里，有单元测试）：
/// 相邻两次加满之间，后一次加满 + 中间所有未加满的油量 ÷ 里程表差。
/// 中间任何一次标记了「上次漏记」或缺里程表，这一段就不算。
enum FuelEconomy {
    static func analyze(entries: [FuelEntry]) -> FuelAnalysis {
        let intervals = CostCalculator.fuelIntervals(entries.map(\.fuelFill))
        let segments = intervals.map { interval in
            FuelSegment(id: interval.endFillID,
                        startDate: interval.startDate,
                        endDate: interval.endDate,
                        distanceKm: interval.distanceKm,
                        liters: interval.liters,
                        cost: interval.cost)
        }
        var economyByEntry: [UUID: Double] = [:]
        for interval in intervals {
            economyByEntry[interval.endFillID] = interval.economy
        }
        return FuelAnalysis(segments: segments, economyByEntryID: economyByEntry)
    }
}

extension FuelEntry {
    /// 给 CostKit 用的加油数据
    var fuelFill: FuelFill {
        FuelFill(id: id,
                 date: date,
                 odometer: odometer > 0 ? odometer : nil,
                 liters: liters,
                 cost: totalCost,
                 isFullTank: isFullTank,
                 missedPrevious: missedPrevious)
    }
}
