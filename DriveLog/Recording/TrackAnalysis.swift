import Foundation
import CoreLocation
import SwiftUI

/// 地图按速度分段上色：<30 / 30–60 / 60–90 / 90–110 / >110 km/h
enum SpeedBand: Int, CaseIterable, Identifiable {
    case crawl, city, suburban, highway, fast

    var id: Int { rawValue }

    static func band(forKmh kmh: Double) -> SpeedBand {
        switch kmh {
        case ..<30: return .crawl
        case ..<60: return .city
        case ..<90: return .suburban
        case ..<110: return .highway
        default: return .fast
        }
    }

    var label: String {
        switch self {
        case .crawl: return "<30"
        case .city: return "30–60"
        case .suburban: return "60–90"
        case .highway: return "90–110"
        case .fast: return ">110"
        }
    }

    var color: Color {
        switch self {
        case .crawl: return Color(red: 0.33, green: 0.52, blue: 0.96)
        case .city: return Color(red: 0.18, green: 0.74, blue: 0.36)
        case .suburban: return Color(red: 0.97, green: 0.78, blue: 0.15)
        case .highway: return Color(red: 1.0, green: 0.52, blue: 0.10)
        case .fast: return Color(red: 0.89, green: 0.16, blue: 0.20)
        }
    }
}

struct SpeedSegment: Identifiable {
    let id: Int
    let band: SpeedBand
    let coordinates: [CLLocationCoordinate2D]
}

struct ChartSample: Identifiable {
    let id: Int
    let date: Date
    let value: Double
}

enum TrackAnalysis {
    /// 每个点的速度（km/h）。没有有效速度时用相邻点推算。
    static func speedsKmh(_ points: [TrackPoint]) -> [Double] {
        var result = [Double](repeating: 0, count: points.count)
        for i in points.indices {
            let p = points[i]
            if p.speed >= 0 {
                result[i] = p.speed * 3.6
            } else if i > 0 {
                let dt = p.timestamp.timeIntervalSince(points[i - 1].timestamp)
                result[i] = dt > 0 ? Geo.distance(points[i - 1], p) / dt * 3.6 : result[i - 1]
            }
        }
        return result
    }

    static func smoothed(_ values: [Double], radius: Int) -> [Double] {
        guard radius > 0, values.count > 2 else { return values }
        var prefix = [Double](repeating: 0, count: values.count + 1)
        for i in values.indices {
            prefix[i + 1] = prefix[i] + values[i]
        }
        var out = values
        for i in values.indices {
            let lo = max(0, i - radius)
            let hi = min(values.count - 1, i + radius)
            out[i] = (prefix[hi + 1] - prefix[lo]) / Double(hi - lo + 1)
        }
        return out
    }

    /// 按速度区间切成多段折线
    static func segments(for points: [TrackPoint], maxPoints: Int = 5000) -> [SpeedSegment] {
        guard points.count >= 2 else { return [] }
        let speeds = smoothed(speedsKmh(points), radius: 2)

        var indices: [Int] = []
        let step = max(1, points.count / maxPoints)
        var i = 0
        while i < points.count {
            indices.append(i)
            i += step
        }
        if indices.last != points.count - 1 {
            indices.append(points.count - 1)
        }

        var segments: [SpeedSegment] = []
        var currentBand = SpeedBand.band(forKmh: speeds[indices[0]])
        var coords: [CLLocationCoordinate2D] = [points[indices[0]].coordinate]
        for idx in indices.dropFirst() {
            let band = SpeedBand.band(forKmh: speeds[idx])
            coords.append(points[idx].coordinate)
            if band != currentBand {
                segments.append(SpeedSegment(id: segments.count, band: currentBand, coordinates: coords))
                coords = [points[idx].coordinate]
                currentBand = band
            }
        }
        if coords.count >= 2 {
            segments.append(SpeedSegment(id: segments.count, band: currentBand, coordinates: coords))
        }
        return segments
    }

    static func speedSamples(for points: [TrackPoint], maxCount: Int = 300) -> [ChartSample] {
        guard !points.isEmpty else { return [] }
        let speeds = smoothed(speedsKmh(points), radius: 1)
        let xy = points.indices.map { XY(x: points[$0].timestamp.timeIntervalSince1970, y: speeds[$0]) }
        return Downsampler.lttb(xy, threshold: maxCount).enumerated().map { index, item in
            ChartSample(id: index, date: Date(timeIntervalSince1970: item.x), value: max(0, item.y))
        }
    }

    static func altitudeSamples(for points: [TrackPoint], maxCount: Int = 300) -> [ChartSample] {
        let valid = points.filter { $0.hasValidAltitude }
        guard !valid.isEmpty else { return [] }
        let xy = valid.map { XY(x: $0.timestamp.timeIntervalSince1970, y: $0.altitude) }
        return Downsampler.lttb(xy, threshold: maxCount).enumerated().map { index, item in
            ChartSample(id: index, date: Date(timeIntervalSince1970: item.x), value: item.y)
        }
    }
}
