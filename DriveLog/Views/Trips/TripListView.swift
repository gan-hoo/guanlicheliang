import SwiftUI
import SwiftData

struct TripListView: View {
    @Environment(\.modelContext) private var context
    @ObservedObject private var recorder = TripRecorder.shared
    @Query(sort: \Trip.startDate, order: .reverse) private var trips: [Trip]
    @Query(sort: \Vehicle.createdAt) private var vehicles: [Vehicle]
    @State private var filterVehicleID: UUID?
    @State private var timeRange: TimeRange = .all
    @State private var displayMode: DisplayMode = .all

    /// 分段控件：全部卡片 / 只看汇总卡（上面的玻璃卡片）
    enum DisplayMode: String, CaseIterable, Identifiable {
        case all = "全部"
        case summary = "汇总"
        var id: String { rawValue }
    }

    /// 时间范围筛选
    enum TimeRange: String, CaseIterable, Identifiable {
        case all = "全部时间"
        case thisMonth = "本月"
        case last3Months = "近 3 个月"
        case thisYear = "今年"
        var id: String { rawValue }

        func contains(_ date: Date) -> Bool {
            let calendar = Calendar.current
            let now = Date()
            switch self {
            case .all:
                return true
            case .thisMonth:
                return calendar.isDate(date, equalTo: now, toGranularity: .month)
            case .last3Months:
                guard let start = calendar.date(byAdding: .month, value: -3, to: now) else { return true }
                return date >= start
            case .thisYear:
                return calendar.isDate(date, equalTo: now, toGranularity: .year)
            }
        }
    }

    private var filteredTrips: [Trip] {
        trips.filter { trip in
            (filterVehicleID == nil || trip.vehicleID == filterVehicleID) && timeRange.contains(trip.startDate)
        }
    }

    private var isFiltering: Bool {
        filterVehicleID != nil || timeRange != .all
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
                            .glassListHeader(topSpacing: Theme.firstCardTopSpacing)
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

                    Section {
                    } header: {
                        Picker("显示", selection: $displayMode) {
                            ForEach(DisplayMode.allCases) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .listHeaderContainer()
                    }

                    if displayMode == .all {
                        ForEach(monthGroups) { group in
                            Section {
                            } header: {
                                monthCard(group)
                                    .listHeaderContainer()
                            }
                        }
                    }
                }
                .listRowBackground(Theme.rowFill)
            }
            .listStyle(.insetGrouped)
            .listSectionSpacing(.custom(16))
            .animation(.easeInOut(duration: 0.25), value: displayMode)
            .tabSwitchEffect(.trips)
            .appBackground()
            .navigationTitle("行程")
            .pageHeader("行程") {
                HeaderButtonGroup {
                    Menu {
                        Picker("车辆", selection: $filterVehicleID) {
                            Text("全部车辆").tag(UUID?.none)
                            ForEach(vehicles) { vehicle in
                                Text(vehicle.displayName).tag(UUID?.some(vehicle.id))
                            }
                        }
                        .pickerStyle(.inline)
                        Picker("时间", selection: $timeRange) {
                            ForEach(TimeRange.allCases) { range in
                                Text(range.rawValue).tag(range)
                            }
                        }
                        .pickerStyle(.inline)
                    } label: {
                        HeaderIcon(systemName: isFiltering ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
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

    /// 下面的列表：每个月一张列表卡（按 UI 规范，系统 SF Pro 字体）
    private func monthCard(_ group: TripMonthGroup) -> some View {
        TripListCard(icon: "calendar",
                     title: group.title,
                     subtitle: "\(group.trips.count) 段 · \(Fmt.km(group.distance / 1000))") {
            ForEach(Array(group.trips.enumerated()), id: \.element.id) { item in
                let trip = item.element
                if item.offset > 0 {
                    TripListDivider()
                }
                NavigationLink {
                    TripDetailView(trip: trip)
                } label: {
                    TripListRow(icon: "car.fill",
                                title: "\(Fmt.dateShort.string(from: trip.startDate)) \(Fmt.weekday.string(from: trip.startDate)) \(Fmt.time.string(from: trip.startDate))",
                                subtitle: trip.routeText ?? "均速 \(Fmt.speed(trip.averageMovingSpeed)) · 最高 \(Fmt.speed(trip.maxSpeed))",
                                value: Fmt.distance(trip.distance),
                                subValue: TripSpecFormat.duration(trip.duration))
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button(role: .destructive) {
                        TripService.delete(trip, context: context)
                    } label: {
                        Label("删除这段行程", systemImage: "trash")
                    }
                }
            }
        }
        .fontDesign(.default)
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
                    HStack(spacing: 3) {
                        Image(systemName: "car.fill")
                        Text(vehicleName)
                    }
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
