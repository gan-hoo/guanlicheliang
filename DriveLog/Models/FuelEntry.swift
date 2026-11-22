import Foundation
import SwiftData

/// 加油记录
@Model
final class FuelEntry {
    var id: UUID = UUID()
    var vehicleID: UUID? = nil
    var date: Date = Date()
    /// 里程表读数（km）
    var odometer: Double = 0
    /// 加油量（升）
    var liters: Double = 0
    /// 单价（每升）
    var pricePerLiter: Double = 0
    /// 总价
    var totalCost: Double = 0
    var fuelTypeRaw: String = FuelType.ulp91.rawValue
    var stationName: String = ""
    var latitude: Double? = nil
    var longitude: Double? = nil
    /// 是否加满
    var isFullTank: Bool = true
    /// 上次加油是否漏记
    var missedPrevious: Bool = false
    var notes: String = ""

    init(vehicleID: UUID? = nil, date: Date = Date()) {
        self.id = UUID()
        self.vehicleID = vehicleID
        self.date = date
    }
}

extension FuelEntry {
    var fuelType: FuelType {
        get { FuelType(rawValue: fuelTypeRaw) ?? .ulp91 }
        set { fuelTypeRaw = newValue.rawValue }
    }
}
