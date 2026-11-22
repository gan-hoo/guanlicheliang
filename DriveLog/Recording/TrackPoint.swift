import Foundation
import CoreLocation

/// 单个 GPS 轨迹点。磁盘上每个点是一行 CSV（逐行追加，断电/被杀最多丢最后几秒）。
struct TrackPoint: Codable, Sendable {
    var timestamp: Date
    var latitude: Double
    var longitude: Double
    /// 海拔（米），verticalAccuracy <= 0 时无效
    var altitude: Double
    var horizontalAccuracy: Double
    var verticalAccuracy: Double
    /// 速度（m/s），< 0 表示无效
    var speed: Double
    /// 速度精度（m/s），< 0 表示无效
    var speedAccuracy: Double
    var course: Double
}

extension TrackPoint {
    init(location: CLLocation) {
        self.init(
            timestamp: location.timestamp,
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            altitude: location.altitude,
            horizontalAccuracy: location.horizontalAccuracy,
            verticalAccuracy: location.verticalAccuracy,
            speed: location.speed,
            speedAccuracy: location.speedAccuracy,
            course: location.course
        )
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var hasValidAltitude: Bool { verticalAccuracy > 0 && verticalAccuracy <= 30 }

    /// 内部存储格式：epoch,lat,lon,alt,hAcc,vAcc,speed,speedAcc,course\n
    var csvLine: String {
        String(format: "%.3f,%.7f,%.7f,%.2f,%.1f,%.1f,%.2f,%.2f,%.1f\n",
               timestamp.timeIntervalSince1970,
               latitude,
               longitude,
               altitude,
               horizontalAccuracy,
               verticalAccuracy,
               speed,
               speedAccuracy,
               course)
    }

    init?(csvLine line: Substring) {
        let parts = line.split(separator: ",", omittingEmptySubsequences: false)
        guard parts.count == 9 else { return nil }
        var values: [Double] = []
        values.reserveCapacity(9)
        for part in parts {
            guard let value = Double(part) else { return nil }
            values.append(value)
        }
        guard abs(values[1]) <= 90, abs(values[2]) <= 180 else { return nil }
        self.init(
            timestamp: Date(timeIntervalSince1970: values[0]),
            latitude: values[1],
            longitude: values[2],
            altitude: values[3],
            horizontalAccuracy: values[4],
            verticalAccuracy: values[5],
            speed: values[6],
            speedAccuracy: values[7],
            course: values[8]
        )
    }
}

enum Geo {
    /// 球面距离（米）
    static func distance(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        let radius: Double = 6_371_008.8
        let toRad: Double = .pi / 180
        let phi1: Double = lat1 * toRad
        let phi2: Double = lat2 * toRad
        let dPhi: Double = (lat2 - lat1) * toRad
        let dLambda: Double = (lon2 - lon1) * toRad
        let sinDPhi: Double = sin(dPhi / 2)
        let sinDLambda: Double = sin(dLambda / 2)
        let a: Double = sinDPhi * sinDPhi + cos(phi1) * cos(phi2) * sinDLambda * sinDLambda
        let c: Double = 2 * atan2(sqrt(a), sqrt(max(0, 1 - a)))
        return radius * c
    }

    static func distance(_ a: TrackPoint, _ b: TrackPoint) -> Double {
        distance(lat1: a.latitude, lon1: a.longitude, lat2: b.latitude, lon2: b.longitude)
    }
}
