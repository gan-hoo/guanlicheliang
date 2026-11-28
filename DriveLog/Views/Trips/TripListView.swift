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
    /// 「某一天」筛选选中的日期
    @State private var selectedDay = Date()
    @State private var showDayPicker = false
    @State private var pickedDay = Date()
    /// 汇总卡里的路线（筛选时间内所有行程）
    @State private var routeSegments: [SpeedSegment] = []
    @State private var routeLoading = false
    @State private var showRouteFullMap = false

    /// 分段控件：全部卡片 / 只看汇总卡（上面的玻璃卡片）
    enum DisplayMode: String, CaseIterable, Identifiable {
        case all = "全部"
        case summary = "汇总"
        var id: String { rawValue }
    }

    /// 时间范围筛选
    enum TimeRange: String, CaseIterable, Identifiable {
        case all = "全部时间"
        case today = "今天"
        case thisMonth = "本月"
        case last3Months = "近 3 个月"
        case thisYear = "今年"
        /// 某一天（日期在 selectedDay），不出现在菜单的选项里，由「选择某一天…」进入
        case day = "某一天"
        var id: String { rawValue }

        static let menuCases: [TimeRange] = [.all, .today, .thisMonth, .last3Months, .thisYear]

        /// 只看一天：列表按这一天显示
        var isSingleDay: Bool { self == .today || self == .day }

        func contains(_ date: Date, day: Date) -> Bool {
            let calendar = Calendar.current
            let now = Date()
            switch self {
            case .all:
                return true
            case .today:
                return calendar.isDate(date, inSameDayAs: now)
            case .day:
                return calendar.isDate(date, inSameDayAs: day)
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
            (filterVehicleID == nil || trip.vehicleID == filterVehicleID)
                && timeRange.contains(trip.startDate, day: selectedDay)
        }
    }

    private var isFiltering: Bool {
        filterVehicleID != nil || timeRange != .all
    }

    private var monthGroups: [TripMonthGroup] {
        if timeRange.isSingleDay {
            // 只看一天：这一天的全部行程放在一张卡里
            let day = timeRange == .today ? Date() : selectedDay
            guard !filteredTrips.isEmpty else { return [] }
            return [TripMonthGroup(id: "day", title: dayTitle(day), trips: filteredTrips)]
        }
        return TripMonthGroup.group(filteredTrips)
    }

    /// 筛选的时间范围，汇总卡的标题
    private var periodTitle: String {
        switch timeRange {
        case .all: return "全部时间"
        case .today: return "今天 · \(dayTitle(Date()))"
        case .day: return dayTitle(selectedDay)
        case .thisMonth: return "本月 · \(Fmt.monthTitle.string(from: Date()))"
        case .last3Months: return "近 3 个月"
        case .thisYear: return "今年 · \(Fmt.yearTitle.string(from: Date()))"
        }
    }

    /// 汇总：筛选的时间范围内所有行程的合计
    private var periodSummaryCard: some View {
        let trips = filteredTrips
        let distance = trips.reduce(0) { $0 + $1.distance }
        let duration = trips.reduce(0) { $0 + $1.duration }
        let moving = trips.reduce(0) { $0 + $1.movingDuration }
        let fastest = trips.max { $0.maxSpeed < $1.maxSpeed }
        var subtitle = "\(trips.count) 段 · \(Fmt.km(distance / 1000))"
        if let filterVehicleID, let name = vehicleName(filterVehicleID) {
            subtitle = "\(name) · " + subtitle
        }
        return TripListCard(icon: "sum", title: periodTitle, subtitle: subtitle) {
            routeMap
            TripListRow(icon: "road.lanes",
                        title: "总里程",
                        subtitle: "\(trips.count) 段行程",
                        value: Fmt.distance(distance),
                        showsChevron: false)
            TripListDivider()
            TripListRow(icon: "clock",
                        title: "总时长",
                        subtitle: "行驶 \(TripSpecFormat.duration(moving))",
                        value: TripSpecFormat.duration(duration),
                        showsChevron: false)
            TripListDivider()
            TripListRow(icon: "speedometer",
                        title: "平均速度",
                        subtitle: "按行驶时长计算",
                        value: Fmt.speed(moving > 0 ? distance / moving : 0),
                        showsChevron: false)
            TripListDivider()
            TripListRow(icon: "bolt",
                        title: "最高速度",
                        subtitle: fastest.map { "\(Fmt.dateShort.string(from: $0.startDate)) \(Fmt.time.string(from: $0.startDate))" } ?? "—",
                        value: Fmt.speed(fastest?.maxSpeed ?? 0),
                        showsChevron: false)
        }
        .fontDesign(.default)
    }

    /// "11月28日 周六"
    private func dayTitle(_ date: Date) -> String {
        "\(Fmt.dateShort.string(from: date)) \(Fmt.weekday.string(from: date))"
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
                            if timeRange.isSingleDay {
                                ContentUnavailableView("这一天没有行程",
                                                       systemImage: "car.rear.road.lane",
                                                       description: Text(dayTitle(timeRange == .today ? Date() : selectedDay)))
                            } else {
                                ContentUnavailableView("还没有行程",
                                                       systemImage: "car.rear.road.lane",
                                                       description: Text("连上 CarPlay 自动记录，或在首页手动开始。"))
                            }
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

                    if displayMode == .summary && !filteredTrips.isEmpty {
                        Section {
                        } header: {
                            periodSummaryCard
                                .listHeaderContainer()
                        }
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
                            ForEach(TimeRange.menuCases) { range in
                                Text(range.rawValue).tag(range)
                            }
                        }
                        .pickerStyle(.inline)
                        Button {
                            pickedDay = timeRange == .day ? selectedDay : Date()
                            showDayPicker = true
                        } label: {
                            if timeRange == .day {
                                Label("某一天：\(dayTitle(selectedDay))", systemImage: "checkmark")
                            } else {
                                Label("选择某一天…", systemImage: "calendar")
                            }
                        }
                    } label: {
                        HeaderIcon(systemName: isFiltering ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    }
                }
            }
            .sheet(isPresented: $showDayPicker) {
                NavigationStack {
                    DatePicker("日期", selection: $pickedDay, in: ...Date(), displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .padding(.horizontal)
                        .navigationTitle("选择某一天")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("取消") { showDayPicker = false }
                            }
                            ToolbarItem(placement: .confirmationAction) {
                                Button("完成") {
                                    selectedDay = pickedDay
                                    timeRange = .day
                                    showDayPicker = false
                                }
                            }
                        }
                }
                .presentationDetents([.large])
            }
            .fullScreenCover(isPresented: $showRouteFullMap) {
                FullScreenTripMap(segments: routeSegments,
                                  start: filteredTrips.last?.startCoordinate,
                                  end: filteredTrips.first?.endCoordinate)
            }
            .task(id: routeKey) {
                await loadRoutes()
            }
        }
    }

    /// 筛选条件或行程变化时重新加载汇总路线
    private var routeKey: String {
        guard displayMode == .summary else { return "off" }
        let trips = filteredTrips
        return [timeRange.rawValue,
                String(selectedDay.timeIntervalSince1970),
                filterVehicleID?.uuidString ?? "",
                String(trips.count),
                trips.first?.id.uuidString ?? "",
                trips.last?.id.uuidString ?? ""].joined(separator: "|")
    }

    /// 读取筛选时间内所有行程的轨迹，合成一张地图。
    /// 行程不多时按每个点的速度上色（和行程详情一样）；超过 30 段时每段行程按平均速度一种颜色，避免地图太卡。
    private func loadRoutes() async {
        guard displayMode == .summary else { return }
        let trips = filteredTrips
        guard !trips.isEmpty else {
            routeSegments = []
            return
        }
        routeSegments = []
        routeLoading = true
        // 从早到晚
        let items = trips.reversed().map { ($0.id, SpeedBand.band(forKmh: $0.averageMovingSpeed * 3.6)) }
        let perTripColors = items.count > 30
        let maxPoints = max(30, 6000 / items.count)
        let result = await Task.detached(priority: .userInitiated) { () -> [SpeedSegment] in
            var all: [SpeedSegment] = []
            for (id, averageBand) in items {
                if Task.isCancelled { break }
                let points = TrackStore.readPoints(for: id)
                for segment in TrackAnalysis.segments(for: points, maxPoints: maxPoints) {
                    if perTripColors, let last = all.last, last.band == averageBand,
                       last.coordinates.last.map({ $0.latitude == segment.coordinates.first?.latitude && $0.longitude == segment.coordinates.first?.longitude }) == true {
                        // 同一段行程按平均速度一种颜色：把相邻的折线接起来，减少地图上的折线数量
                        all[all.count - 1] = SpeedSegment(id: last.id, band: averageBand,
                                                          coordinates: last.coordinates + segment.coordinates.dropFirst())
                    } else {
                        all.append(SpeedSegment(id: all.count,
                                                band: perTripColors ? averageBand : segment.band,
                                                coordinates: segment.coordinates))
                    }
                }
            }
            return all
        }.value
        guard !Task.isCancelled else { return }
        routeSegments = result
        routeLoading = false
    }

    /// 汇总卡里的地图
    @ViewBuilder
    private var routeMap: some View {
        Group {
            if routeLoading && routeSegments.isEmpty {
                ZStack {
                    Color(uiColor: .tertiarySystemFill)
                    ProgressView()
                }
            } else if routeSegments.isEmpty {
                ZStack {
                    Color(uiColor: .tertiarySystemFill)
                    Text("没有轨迹数据")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                TripMapView(segments: routeSegments,
                            start: filteredTrips.last?.startCoordinate,
                            end: filteredTrips.first?.endCoordinate,
                            lineWidth: 4)
                    .id(routeKey)
                    .overlay(alignment: .topTrailing) {
                        Button {
                            showRouteFullMap = true
                        } label: {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.body.weight(.semibold))
                                .frame(width: 40, height: 40)
                                .glassCircle(interactive: false)
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .padding(10)
                    }
                    .overlay(alignment: .bottom) {
                        SpeedLegendView()
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .glassCapsule()
                            .padding(10)
                    }
            }
        }
        .frame(height: 280)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, TripSpec.horizontalPadding)
        .padding(.bottom, 4)
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
                                title: timeRange.isSingleDay
                                    ? "\(Fmt.time.string(from: trip.startDate))–\(Fmt.time.string(from: trip.endDate))"
                                    : "\(Fmt.dateShort.string(from: trip.startDate)) \(Fmt.weekday.string(from: trip.startDate)) \(Fmt.time.string(from: trip.startDate))",
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
