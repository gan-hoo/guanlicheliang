import Foundation
import CoreLocation
import MapKit

/// 单次定位（加油表单默认用当前位置）
@MainActor
final class OneShotLocation: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation?, Never>?

    func fetch(timeout: TimeInterval = 10) async -> CLLocation? {
        let status = manager.authorizationStatus
        guard status == .authorizedAlways || status == .authorizedWhenInUse else { return nil }
        if let cached = manager.location, Date().timeIntervalSince(cached.timestamp) < 60, cached.horizontalAccuracy <= 100 {
            return cached
        }
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        return await withCheckedContinuation { (continuation: CheckedContinuation<CLLocation?, Never>) in
            self.continuation = continuation
            manager.requestLocation()
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                self.finish(nil)
            }
        }
    }

    private func finish(_ location: CLLocation?) {
        continuation?.resume(returning: location)
        continuation = nil
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let last = locations.last
        MainActor.assumeIsolated {
            self.finish(last)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        MainActor.assumeIsolated {
            self.finish(nil)
        }
    }
}

enum NearbyPlaces {
    /// 附近的加油站名称（MapKit 兴趣点）
    static func gasStations(near coordinate: CLLocationCoordinate2D, radius: CLLocationDistance = 600) async -> [String] {
        let request = MKLocalPointsOfInterestRequest(center: coordinate, radius: radius)
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: [.gasStation])
        let search = MKLocalSearch(request: request)
        guard let response = try? await search.start() else { return [] }
        let origin = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let sorted = response.mapItems.sorted { a, b in
            let da = a.placemark.location?.distance(from: origin) ?? .greatestFiniteMagnitude
            let db = b.placemark.location?.distance(from: origin) ?? .greatestFiniteMagnitude
            return da < db
        }
        var names: [String] = []
        for item in sorted {
            if let name = item.name, !name.isEmpty, !names.contains(name) {
                names.append(name)
            }
        }
        return Array(names.prefix(6))
    }
}
