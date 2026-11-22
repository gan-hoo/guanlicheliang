import SwiftUI
import MapKit

/// 按速度分段上色的轨迹地图，标出起点和终点
struct TripMapView: View {
    let segments: [SpeedSegment]
    let start: CLLocationCoordinate2D?
    let end: CLLocationCoordinate2D?
    var lineWidth: CGFloat = 5

    var body: some View {
        Map(initialPosition: .automatic) {
            ForEach(segments) { segment in
                MapPolyline(coordinates: segment.coordinates)
                    .stroke(segment.band.color, lineWidth: lineWidth)
            }
            if let start {
                Marker("起点", systemImage: "flag.fill", coordinate: start)
                    .tint(.green)
            }
            if let end {
                Marker("终点", systemImage: "flag.checkered", coordinate: end)
                    .tint(.red)
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .mapControls {
            MapCompass()
            MapScaleView()
        }
    }
}

/// 速度图例
struct SpeedLegendView: View {
    var body: some View {
        HStack(spacing: 10) {
            ForEach(SpeedBand.allCases) { band in
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(band.color)
                        .frame(width: 14, height: 6)
                    Text(band.label)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            Text("km/h")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

/// 全屏地图
struct FullScreenTripMap: View {
    let segments: [SpeedSegment]
    let start: CLLocationCoordinate2D?
    let end: CLLocationCoordinate2D?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            TripMapView(segments: segments, start: start, end: end, lineWidth: 6)
                .ignoresSafeArea(edges: .bottom)
                .safeAreaInset(edge: .bottom) {
                    SpeedLegendView()
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .glassCapsule()
                        .padding()
                }
                .navigationTitle("轨迹")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完成") { dismiss() }
                    }
                }
        }
    }
}
