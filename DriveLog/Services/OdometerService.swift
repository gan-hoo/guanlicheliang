import Foundation
import SwiftData

struct OdometerReading {
    var date: Date
    var value: Double
    var source: String
}

/// 估算当前里程：最近一次手动填写的里程表读数 + 之后记录到的行程距离。
/// 加油记录里的里程表不参与估算（加油记录常常是事后补的，时间和读数对不上），只用来算油耗。
enum OdometerService {
    static func latestReading(vehicle: Vehicle, fuel: [FuelEntry], expenses: [Expense]) -> OdometerReading {
        let vid = vehicle.id
        var best = OdometerReading(date: vehicle.initialOdometerDate, value: vehicle.initialOdometer, source: "初始读数")
        if let value = vehicle.odometerCalibration, let date = vehicle.odometerCalibrationDate, date >= best.date {
            best = OdometerReading(date: date, value: value, source: "手动校正")
        }
        for expense in expenses where expense.vehicleID == vid && expense.date >= best.date {
            guard let value = expense.odometer, value > 0 else { continue }
            best = OdometerReading(date: expense.date, value: value, source: "费用记录")
        }
        return best
    }

    /// 读数之后记录到的行程距离（km）
    static func tripKilometers(after date: Date, vehicleID: UUID, trips: [Trip]) -> Double {
        var meters = 0.0
        for trip in trips where trip.vehicleID == vehicleID && trip.startDate >= date {
            meters += trip.distance
        }
        return meters / 1000
    }

    static func estimate(vehicle: Vehicle, trips: [Trip], fuel: [FuelEntry], expenses: [Expense]) -> Double {
        let reading = latestReading(vehicle: vehicle, fuel: fuel, expenses: expenses)
        return reading.value + tripKilometers(after: reading.date, vehicleID: vehicle.id, trips: trips)
    }

    @MainActor
    static func estimate(vehicle: Vehicle, context: ModelContext) -> Double {
        let trips = (try? context.fetch(FetchDescriptor<Trip>())) ?? []
        let fuel = (try? context.fetch(FetchDescriptor<FuelEntry>())) ?? []
        let expenses = (try? context.fetch(FetchDescriptor<Expense>())) ?? []
        return estimate(vehicle: vehicle, trips: trips, fuel: fuel, expenses: expenses)
    }
}
