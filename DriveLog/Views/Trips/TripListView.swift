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
                Section {
                    summaryHeader
                }

                if recorder.isRecording {
                    Section {
                        HStack {
                            Image(systemName: "record.circle")
                                .foregroundStyle(.red)
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
            .listStyle(.insetGrouped)
            .appBackground()
            .navigationTitle("行程")
            .toolbar {
                if vehicles.count > 1 {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Picker("车辆", selection: $filterVehicleID) {
                                Text("全部车辆").tag(UUID?.none)
                                ForEach(vehicles) { vehicle in
                                    Text(vehicle.displayName).tag(UUID?.some(vehicle.id))
                                }
                            }
                        } label: {
                            Image(systemName: filterVehicleID == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                        }
                    }
                }
            }
        }
    }

    private var summaryHeader: some View {
        let totalDistance = filteredTrips.reduce(0) { $0 + $1.distance }
        let totalDuration = filteredTrips.reduce(0) { $0 + $1.duration }
        return VStack(alignment: .leading, spacing: 8) {
            Text("累计里程")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(Fmt.km(totalDistance / 1000))
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .monospacedDigit()
            HStack(spacing: 16) {
                Label("\(filteredTrips.count) 段行程", systemImage: "map")
                Label(Fmt.duration(totalDuration), systemImage: "clock")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
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
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(Fmt.dateTimeShort.string(from: trip.startDate))
                    .font(.headline)
                Text(Fmt.weekday.string(from: trip.startDate))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(Fmt.distance(trip.distance))
                    .font(.headline)
                    .monospacedDigit()
            }
            if let route = trip.routeText {
                Text(route)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            HStack(spacing: 12) {
                Label(Fmt.duration(trip.duration), systemImage: "clock")
                Label("均 \(Fmt.speed(trip.averageMovingSpeed))", systemImage: "speedometer")
                Label("最高 \(Fmt.speed(trip.maxSpeed))", systemImage: "bolt")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            if let vehicleName {
                Text(vehicleName)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.accentColor.opacity(0.12)))
            }
        }
        .padding(.vertical, 2)
    }
}
