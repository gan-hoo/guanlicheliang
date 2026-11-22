import Foundation

/// 逐点累加行程统计，并做 GPS 过滤。
/// 实时记录和「被杀后从文件恢复」用的是同一套逻辑，结果一致。
struct TripAccumulator {
    /// 水平精度超过 50 m 的点丢弃（在 TripRecorder 里过滤）
    static let maxHorizontalAccuracy: Double = 50
    /// 停车漂移判定：速度 < 0.8 m/s 且相对上一个计数点位移 < 15 m
    static let stationarySpeed: Double = 0.8
    static let stationaryDistance: Double = 15
    /// 隐含速度超过 250 km/h 视为跳点
    static let maxPlausibleSpeed: Double = 250 / 3.6
    /// 最高速度只用 speedAccuracy 可靠的点
    static let maxReliableSpeedAccuracy: Double = 2.0
    /// 海拔累计爬升的迟滞阈值（米）
    static let elevationThreshold: Double = 5

    private(set) var distance: Double = 0
    private(set) var movingDuration: Double = 0
    private(set) var maxSpeed: Double = 0
    private(set) var minAltitude: Double?
    private(set) var maxAltitude: Double?
    private(set) var elevationGain: Double = 0
    private(set) var currentAltitude: Double?
    private(set) var first: TrackPoint?
    private(set) var last: TrackPoint?
    private(set) var pointCount: Int = 0

    /// 上一个「计入距离」的点
    private var anchor: TrackPoint?
    private var altitudeReference: Double?

    var averageMovingSpeed: Double {
        movingDuration > 0 ? distance / movingDuration : 0
    }

    /// 加入一个点。返回 false 表示这是跳点/重复点，不应写入轨迹。
    @discardableResult
    mutating func add(_ point: TrackPoint) -> Bool {
        if let previous = last {
            let dt = point.timestamp.timeIntervalSince(previous.timestamp)
            if dt <= 0 { return false }

            let segment = Geo.distance(previous, point)
            let impliedSpeed = segment / dt
            // 跳点：与上一个点之间的隐含速度过高
            if impliedSpeed > Self.maxPlausibleSpeed { return false }

            let speedEstimate = point.speed >= 0 ? point.speed : impliedSpeed
            let anchorPoint = anchor ?? previous
            let fromAnchor = Geo.distance(anchorPoint, point)
            let isStationary = speedEstimate < Self.stationarySpeed && fromAnchor < Self.stationaryDistance

            if !isStationary {
                distance += fromAnchor
                anchor = point
                let moving = impliedSpeed >= Self.stationarySpeed || (speedEstimate >= Self.stationarySpeed && dt <= 5)
                if moving {
                    movingDuration += dt
                }
            }
        } else {
            first = point
            anchor = point
        }

        if point.speed >= 0,
           point.speedAccuracy >= 0,
           point.speedAccuracy <= Self.maxReliableSpeedAccuracy,
           point.speed <= Self.maxPlausibleSpeed {
            maxSpeed = max(maxSpeed, point.speed)
        }

        if point.hasValidAltitude {
            let altitude = point.altitude
            currentAltitude = altitude
            minAltitude = min(minAltitude ?? altitude, altitude)
            maxAltitude = max(maxAltitude ?? altitude, altitude)
            if let reference = altitudeReference {
                if altitude - reference >= Self.elevationThreshold {
                    elevationGain += altitude - reference
                    altitudeReference = altitude
                } else if reference - altitude >= Self.elevationThreshold {
                    altitudeReference = altitude
                }
            } else {
                altitudeReference = altitude
            }
        }

        last = point
        pointCount += 1
        return true
    }
}
