import Foundation
import SwiftData

/// 车辆
@Model
final class Vehicle {
    var id: UUID = UUID()
    var nickname: String = ""
    var brand: String = ""
    var modelName: String = ""
    var year: Int? = nil
    var plate: String = ""
    var fuelTypeRaw: String = FuelType.ulp91.rawValue
    /// 油箱容量（升）
    var tankCapacity: Double? = nil
    var purchaseDate: Date? = nil
    var purchasePrice: Double? = nil
    /// 初始里程表读数（km）及其对应时间
    var initialOdometer: Double = 0
    var initialOdometerDate: Date = Date()
    /// 手动校正的里程表读数（km）及时间
    var odometerCalibration: Double? = nil
    var odometerCalibrationDate: Date? = nil
    var notes: String = ""
    @Attribute(.externalStorage) var photoData: Data? = nil
    var createdAt: Date = Date()

    init(nickname: String = "", brand: String = "", modelName: String = "") {
        self.id = UUID()
        self.nickname = nickname
        self.brand = brand
        self.modelName = modelName
        self.createdAt = Date()
        self.initialOdometerDate = Date()
    }
}

extension Vehicle {
    var fuelType: FuelType {
        get { FuelType(rawValue: fuelTypeRaw) ?? .ulp91 }
        set { fuelTypeRaw = newValue.rawValue }
    }

    var displayName: String {
        let trimmed = nickname.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { return trimmed }
        let fallback = [brand, modelName].filter { !$0.isEmpty }.joined(separator: " ")
        return fallback.isEmpty ? "未命名车辆" : fallback
    }

    var subtitle: String {
        var parts: [String] = []
        if !brand.isEmpty { parts.append(brand) }
        if !modelName.isEmpty { parts.append(modelName) }
        if let year { parts.append("\(year)") }
        return parts.joined(separator: " ")
    }
}
