import Foundation
import SwiftData
import CoreLocation

/// 行程概要（GPS 轨迹点单独存成文件，见 TrackStore）
@Model
final class Trip {
    var id: UUID = UUID()
    var vehicleID: UUID? = nil
    var startDate: Date = Date()
    var endDate: Date = Date()
    /// 距离（米）
    var distance: Double = 0
    /// 总时长（秒）
    var duration: Double = 0
    /// 行驶时长（秒，不含停车）
    var movingDuration: Double = 0
    /// 最高速度（m/s）
    var maxSpeed: Double = 0
    /// 行驶中平均速度（m/s）
    var averageMovingSpeed: Double = 0
    var minAltitude: Double? = nil
    var maxAltitude: Double? = nil
    /// 累计爬升（米）
    var elevationGain: Double = 0
    var startLatitude: Double? = nil
    var startLongitude: Double? = nil
    var endLatitude: Double? = nil
    var endLongitude: Double? = nil
    var startAddress: String? = nil
    var endAddress: String? = nil
    var pointCount: Int = 0
    var notes: String = ""

    init(id: UUID = UUID(), vehicleID: UUID? = nil, startDate: Date = Date(), endDate: Date = Date()) {
        self.id = id
        self.vehicleID = vehicleID
        self.startDate = startDate
        self.endDate = endDate
    }
}

extension Trip {
    var distanceKm: Double { distance / 1000 }

    var startCoordinate: CLLocationCoordinate2D? {
        guard let startLatitude, let startLongitude else { return nil }
        return CLLocationCoordinate2D(latitude: startLatitude, longitude: startLongitude)
    }

    var endCoordinate: CLLocationCoordinate2D? {
        guard let endLatitude, let endLongitude else { return nil }
        return CLLocationCoordinate2D(latitude: endLatitude, longitude: endLongitude)
    }

    /// 「起点 → 终点」文字（地址反查成功后才有）
    var routeText: String? {
        let start = (startAddress ?? "").trimmingCharacters(in: .whitespaces)
        let end = (endAddress ?? "").trimmingCharacters(in: .whitespaces)
        if start.isEmpty && end.isEmpty { return nil }
        return "\(start.isEmpty ? "未知" : start) → \(end.isEmpty ? "未知" : end)"
    }

    /// 用累加器的统计结果填充
    func apply(_ acc: TripAccumulator) {
        distance = acc.distance
        duration = max(0, endDate.timeIntervalSince(startDate))
        movingDuration = min(acc.movingDuration, duration > 0 ? duration : acc.movingDuration)
        maxSpeed = acc.maxSpeed
        averageMovingSpeed = movingDuration > 0 ? distance / movingDuration : 0
        minAltitude = acc.minAltitude
        maxAltitude = acc.maxAltitude
        elevationGain = acc.elevationGain
        startLatitude = acc.first?.latitude
        startLongitude = acc.first?.longitude
        endLatitude = acc.last?.latitude
        endLongitude = acc.last?.longitude
        pointCount = acc.pointCount
    }
}
