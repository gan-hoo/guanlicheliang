import Foundation

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

/// 油耗用「满箱到满箱」法：两次加满之间（不含上一次、含这一次）的所有加油量 ÷ 这段里程。
/// 中间任何一次标记了「上次漏记」，这一段就不算。
enum FuelEconomy {
    static func analyze(entries: [FuelEntry]) -> FuelAnalysis {
        let sorted = entries.sorted { lhs, rhs in
            if lhs.date != rhs.date { return lhs.date < rhs.date }
            return lhs.odometer < rhs.odometer
        }
        var segments: [FuelSegment] = []
        var economyByEntry: [UUID: Double] = [:]
        var lastFullIndex: Int?

        for index in sorted.indices {
            let entry = sorted[index]
            guard entry.isFullTank else { continue }
            if let start = lastFullIndex {
                let range = sorted[(start + 1)...index]
                let hasMissed = range.contains { $0.missedPrevious }
                let distance = entry.odometer - sorted[start].odometer
                if !hasMissed && distance > 0 {
                    let liters = range.reduce(0) { $0 + $1.liters }
                    let cost = range.reduce(0) { $0 + $1.totalCost }
                    let economy = liters / distance * 100
                    if liters > 0 && economy > 0.5 && economy < 100 {
                        segments.append(FuelSegment(id: entry.id,
                                                    startDate: sorted[start].date,
                                                    endDate: entry.date,
                                                    distanceKm: distance,
                                                    liters: liters,
                                                    cost: cost))
                        economyByEntry[entry.id] = economy
                    }
                }
            }
            lastFullIndex = index
        }
        return FuelAnalysis(segments: segments, economyByEntryID: economyByEntry)
    }
}
