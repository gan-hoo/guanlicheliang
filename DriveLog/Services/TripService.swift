import Foundation
import SwiftData
import CoreLocation

@MainActor
enum TripService {
    /// 删除行程：同时删除内部轨迹和导出的 GPX/CSV
    static func delete(_ trip: Trip, context: ModelContext) {
        TrackStore.delete(trip.id)
        TripExporter.deleteExports(id: trip.id, startDate: trip.startDate)
        context.delete(trip)
        try? context.save()
    }

    /// 反查起终点地名（失败时保持 nil，下次打开 App 再试）
    static func geocode(_ trip: Trip) async {
        if trip.startAddress == nil, let lat = trip.startLatitude, let lon = trip.startLongitude {
            trip.startAddress = await Geocoder.placeName(latitude: lat, longitude: lon)
        }
        if trip.endAddress == nil, let lat = trip.endLatitude, let lon = trip.endLongitude {
            trip.endAddress = await Geocoder.placeName(latitude: lat, longitude: lon)
        }
    }

    static func fillMissingAddresses(context: ModelContext, limit: Int = 6) async {
        let descriptor = FetchDescriptor<Trip>(sortBy: [SortDescriptor(\.startDate, order: .reverse)])
        guard let trips = try? context.fetch(descriptor) else { return }
        var processed = 0
        for trip in trips where trip.startAddress == nil || trip.endAddress == nil {
            if processed >= limit { break }
            guard trip.startLatitude != nil else { continue }
            processed += 1
            await geocode(trip)
        }
        if processed > 0 {
            try? context.save()
        }
    }
}

enum Geocoder {
    /// 成功但没有名字时返回 ""（不再重试）；网络失败返回 nil
    static func placeName(latitude: Double, longitude: Double) async -> String? {
        let geocoder = CLGeocoder()
        let location = CLLocation(latitude: latitude, longitude: longitude)
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            guard let placemark = placemarks.first else { return "" }
            var parts: [String] = []
            if let area = placemark.subLocality ?? placemark.locality {
                parts.append(area)
            }
            if let street = placemark.thoroughfare ?? placemark.name, !parts.contains(street) {
                parts.append(street)
            }
            return parts.joined(separator: " ")
        } catch {
            return nil
        }
    }
}
