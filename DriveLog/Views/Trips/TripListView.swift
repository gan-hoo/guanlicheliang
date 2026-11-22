import SwiftUI
import SwiftData

struct TripListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Trip.startDate, order: .reverse) private var trips: [Trip]
    @Query(sort: \Vehicle.createdAt) private var vehicles: [Vehicle]

    /// 分段控件：全部卡片 / 只看汇总卡
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

    @State private var displayMode: DisplayMode = .all
    @State private var filterVehicleID: UUID?
    @State private var timeRange: TimeRange = .all

    private var filteredTrips: [Trip] {
        trips.filter { trip in
            (filterVehicleID == nil || trip.vehicleID == filterVehicleID) && timeRange.contains(trip.startDate)
        }
    }

    private var isFiltering: Bool {
        filterVehicleID != nil || timeRange != .all
    }

    private var filterDescription: String {
        let vehicleText = filterVehicleID.flatMap { id in vehicles.first(where: { $0.id == id })?.displayName } ?? "全部车辆"
        return "\(vehicleText) · \(timeRange.rawValue)"
    }

    var body: some View {
        let shown = filteredTrips
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Picker("显示", selection: $displayMode) {
                        ForEach(DisplayMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    summaryCard(shown)

                    if displayMode == .all {
                        ForEach(TripMonthGroup.group(shown)) { group in
                            monthCard(group)
                        }
                    }

                    if shown.isEmpty {
                        Text(isFiltering ? "没有符合筛选条件的行程。" : "还没有行程。连上 CarPlay 会自动记录，也可以在首页手动开始。")
                            .font(.system(size: 13))
                            .foregroundStyle(TripSpec.hint)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 8)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, Theme.firstCardTopSpacing)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .background { AppBackground() }
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
            .fontDesign(.default)
            .tint(TripSpec.primary)
        }
    }

    // MARK: - 汇总卡

    private func summaryCard(_ shown: [Trip]) -> some View {
        let count = shown.count
        let distance = shown.reduce(0) { $0 + $1.distance }
        let duration = shown.reduce(0) { $0 + $1.duration }
        let moving = shown.reduce(0) { $0 + $1.movingDuration }
        let maxSpeed = shown.map(\.maxSpeed).max() ?? 0
        let averageSpeed = moving > 0 ? distance / moving : 0
        return TripListCard(icon: "chart.bar.fill", title: "行程汇总", subtitle: filterDescription) {
            NavigationLink {
                StatsView(initialVehicleID: filterVehicleID)
            } label: {
                TripListRow(icon: "road.lanes",
                            title: "累计里程",
                            subtitle: "共 \(count) 段行程",
                            value: Fmt.km(distance / 1000),
                            subValue: count > 0 ? "平均每段 \(Fmt.km(distance / 1000 / Double(count)))" : nil)
            }
            .buttonStyle(.plain)
            TripListDivider()
            NavigationLink {
                StatsView(initialVehicleID: filterVehicleID)
            } label: {
                TripListRow(icon: "clock",
                            title: "总时长",
                            subtitle: "行驶 \(TripSpecFormat.duration(moving))",
                            value: TripSpecFormat.duration(duration))
            }
            .buttonStyle(.plain)
            TripListDivider()
            NavigationLink {
                StatsView(initialVehicleID: filterVehicleID)
            } label: {
                TripListRow(icon: "speedometer",
                            title: "平均速度",
                            subtitle: "按行驶时间计算",
                            value: Fmt.speed(averageSpeed),
                            subValue: "最高 \(Fmt.speed(maxSpeed))")
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - 月份卡

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
