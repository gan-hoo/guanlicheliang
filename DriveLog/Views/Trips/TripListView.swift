import SwiftUI
import SwiftData

struct TripListView: View {
    @Environment(\.modelContext) private var context
    @ObservedObject private var recorder = TripRecorder.shared
    @Query(sort: \Trip.startDate, order: .reverse) private var trips: [Trip]
    @Query(sort: \Vehicle.createdAt) private var vehicles: [Vehicle]
    @State private var filterVehicleID: UUID?

    private var filteredTrips: [Trip] {
        guard let filterVehicleID else { return trips }
        return trips.filter { $0.vehicleID == filterVehicleID }
    }

    private var monthGroups: [TripMonthGroup] {
        TripMonthGroup.group(filteredTrips)
    }

    var body: some View {
        NavigationStack {
            List {
                Group {
                    Section {
                    } header: {
                        summaryHeader
                            .glassListHeader()
                    }

                    if recorder.isRecording {
                        Section {
                            HStack {
                                Image(systemName: "record.circle.fill")
                                    .foregroundStyle(Theme.record)
                                    .symbolEffect(.pulse, options: .repeating)
                                Text("正在记录：\(Fmt.distance(recorder.distance))")
                                Spacer()
                                Text("在首页查看")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    if filteredTrips.isEmpty {
                        Section {
                            ContentUnavailableView("还没有行程",
                                                   systemImage: "car.rear.road.lane",
                                                   description: Text("连上 CarPlay 自动记录，或在首页手动开始。"))
                        }
                    }

                    ForEach(monthGroups) { group in
                        Section {
                            ForEach(group.trips) { trip in
                                NavigationLink {
                                    TripDetailView(trip: trip)
                                } label: {
                                    TripRow(trip: trip, vehicleName: vehicles.count > 1 ? vehicleName(trip.vehicleID) : nil)
                                }
                            }
                            .onDelete { offsets in
                                delete(group.trips, at: offsets)
                            }
                        } header: {
                            HStack {
                                Text(group.title)
                                Spacer()
                                Text("\(group.trips.count) 段 · \(Fmt.km(group.distance / 1000))")
                            }
                        }
                    }
                }
                .listRowBackground(Theme.rowFill)
            }
            .listStyle(.insetGrouped)
            .appBackground()
            .navigationTitle("行程")
            .pageHeader("行程") {
                if vehicles.count > 1 {
                    HeaderButtonGroup {
                        Menu {
                            Picker("车辆", selection: $filterVehicleID) {
                                Text("全部车辆").tag(UUID?.none)
                                ForEach(vehicles) { vehicle in
                                    Text(vehicle.displayName).tag(UUID?.some(vehicle.id))
                                }
                            }
                        } label: {
                            HeaderIcon(systemName: filterVehicleID == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                        }
                    }
                }
            }
        }
    }

    private var summaryHeader: some View {
        let totalDistance = filteredTrips.reduce(0) { $0 + $1.distance }
        let totalDuration = filteredTrips.reduce(0) { $0 + $1.duration }
        let calendar = Calendar.current
        let monthDistance = filteredTrips
            .filter { calendar.isDate($0.startDate, equalTo: Date(), toGranularity: .month) }
            .reduce(0) { $0 + $1.distance }
        return VStack(alignment: .leading, spacing: 12) {
            Text("累计里程")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(Fmt.number(totalDistance / 1000, decimals: 1))
                    .font(.numeric(44, weight: .bold))
                    .foregroundStyle(Theme.brandGradient)
                    .contentTransition(.numericText())
                Text("km")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                SummaryChip(text: "\(filteredTrips.count) 段", systemImage: "map.fill", tint: Theme.altitude)
                SummaryChip(text: Fmt.duration(totalDuration), systemImage: "clock.fill", tint: Theme.duration)
                SummaryChip(text: "本月 \(Fmt.km(monthDistance / 1000))", systemImage: "calendar", tint: Theme.distance)
            }
        }
        .animation(.snappy, value: totalDistance)
    }

    private func vehicleName(_ id: UUID?) -> String? {
        guard let id else { return "未指定车辆" }
        return vehicles.first(where: { $0.id == id })?.displayName
    }

    private func delete(_ groupTrips: [Trip], at offsets: IndexSet) {
        for index in offsets {
            TripService.delete(groupTrips[index], context: context)
        }
    }
}

struct TripMonthGroup: Identifiable {
    let id: String
    let title: String
    let trips: [Trip]

    var distance: Double { trips.reduce(0) { $0 + $1.distance } }

    /// trips 已按时间倒序
    static func group(_ trips: [Trip]) -> [TripMonthGroup] {
        let calendar = Calendar.current
        var groups: [TripMonthGroup] = []
        var currentKey = ""
        var currentTitle = ""
        var bucket: [Trip] = []
        for trip in trips {
            let comps = calendar.dateComponents([.year, .month], from: trip.startDate)
            let key = "\(comps.year ?? 0)-\(comps.month ?? 0)"
            if key != currentKey {
                if !bucket.isEmpty {
                    groups.append(TripMonthGroup(id: currentKey, title: currentTitle, trips: bucket))
                }
                currentKey = key
                currentTitle = Fmt.monthTitle.string(from: trip.startDate)
                bucket = []
            }
            bucket.append(trip)
        }
        if !bucket.isEmpty {
            groups.append(TripMonthGroup(id: currentKey, title: currentTitle, trips: bucket))
        }
        return groups
    }
}

struct TripRow: View {
    let trip: Trip
    let vehicleName: String?

    var body: some View {
        HStack(spacing: 12) {
            DateBadge(date: trip.startDate,
                      tint: SpeedBand.band(forKmh: trip.averageMovingSpeed * 3.6).color)
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    Text(Fmt.distance(trip.distance))
                        .font(.numeric(19, weight: .bold))
                        .monospacedDigit()
                    Spacer()
                    Text("\(Fmt.time.string(from: trip.startDate))–\(Fmt.time.string(from: trip.endDate))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                if let route = trip.routeText {
                    Text(route)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                HStack(spacing: 12) {
                    MetricLabel(text: Fmt.duration(trip.duration), systemImage: "clock.fill", tint: Theme.duration)
                    MetricLabel(text: Fmt.speed(trip.averageMovingSpeed), systemImage: "speedometer", tint: Theme.speed)
                    MetricLabel(text: Fmt.speed(trip.maxSpeed), systemImage: "bolt.fill", tint: Theme.maxSpeed)
                }
                if let vehicleName {
                    Label(vehicleName, systemImage: "car.fill")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Theme.accent.opacity(0.12)))
                }
            }
        }
        .padding(.vertical, 3)
    }
}

/// 列表头部的小胶囊
struct SummaryChip: View {
    let text: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
            Text(text)
                .lineLimit(1)
        }
        .font(.caption.weight(.medium))
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Capsule().fill(tint.opacity(0.12)))
    }
}
