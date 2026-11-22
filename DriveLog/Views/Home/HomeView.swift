import SwiftUI
import SwiftData

struct HomeView: View {
    @ObservedObject private var recorder = TripRecorder.shared
    @Query(sort: \Vehicle.createdAt) private var vehicles: [Vehicle]
    @Query(sort: \Trip.startDate, order: .reverse) private var trips: [Trip]
    @Query(sort: \FuelEntry.date) private var fuelEntries: [FuelEntry]
    @Query(sort: \Expense.date) private var expenses: [Expense]
    @Query private var reminders: [MaintenanceReminder]
    @Query(sort: \ExpenseCategory.sortOrder) private var categories: [ExpenseCategory]
    @AppStorage(AppSettings.currentVehicleKey) private var currentVehicleIDString: String = ""
    @AppStorage(AppSettings.currencyKey) private var currencyCode: String = AppSettings.defaultCurrency

    @State private var showStopConfirm = false
    @State private var showAddVehicle = false

    private var currentVehicle: Vehicle? {
        if let id = UUID(uuidString: currentVehicleIDString),
           let vehicle = vehicles.first(where: { $0.id == id }) {
            return vehicle
        }
        return vehicles.first
    }

    private var recordingVehicleName: String {
        guard let id = recorder.activeVehicleID,
              let vehicle = vehicles.first(where: { $0.id == id }) else { return "未指定车辆" }
        return vehicle.displayName
    }

    var body: some View {
        NavigationStack {
            // 和行程 / 加油 / 费用页一样：卡片放在列表的分区标题里，位置和宽度完全一致
            List {
                Section {
                } header: {
                    VStack(spacing: 0) {
                        PermissionBanner()
                        Group {
                            if recorder.isRecording {
                                RecordingPanel(recorder: recorder, vehicleName: recordingVehicleName) {
                                    showStopConfirm = true
                                }
                                .transition(.asymmetric(insertion: .scale(scale: 0.94).combined(with: .opacity),
                                                        removal: .scale(scale: 0.98).combined(with: .opacity)))
                            } else if let vehicle = currentVehicle {
                                IdleHero(vehicle: vehicle,
                                         vehicles: vehicles,
                                         odometer: OdometerService.estimate(vehicle: vehicle, trips: trips, fuel: fuelEntries, expenses: expenses),
                                         onSelectVehicle: { currentVehicleIDString = $0.uuidString },
                                         onStart: { recorder.startRecording(trigger: .manual) })
                                .transition(.asymmetric(insertion: .scale(scale: 0.96).combined(with: .opacity),
                                                        removal: .opacity))
                            } else {
                                addVehiclePrompt
                            }
                        }
                        .animation(Theme.spring, value: recorder.isRecording)
                    }
                    .listHeaderContainer(topSpacing: Theme.firstCardTopSpacing)
                }

                if let vehicle = currentVehicle {
                    Section {
                    } header: {
                        VehicleOverviewCard(vehicle: vehicle, trips: trips, fuel: fuelEntries, expenses: expenses)
                            .listHeaderContainer()
                    }
                }

                let upcoming = ReminderEngine.upcomingItems(expenses: expenses, reminders: reminders,
                                                            categories: categories, vehicles: vehicles,
                                                            trips: trips, fuel: fuelEntries)
                if !upcoming.isEmpty {
                    Section {
                    } header: {
                        upcomingCard(Array(upcoming.prefix(4)))
                            .listHeaderContainer()
                    }
                }

                if let last = trips.first {
                    Section {
                    } header: {
                        NavigationLink {
                            TripDetailView(trip: last)
                        } label: {
                            LastTripCard(trip: last)
                        }
                        .buttonStyle(.plain)
                        .listHeaderContainer()
                    }
                }
            }
            .listStyle(.insetGrouped)
            .listSectionSpacing(.custom(Theme.spacing))
            .scrollContentBackground(.hidden)
            .scrollIndicators(.hidden)
            .background { AppBackground() }
            .navigationTitle("行车记录")
            .pageHeader("行车记录")
            .sensoryFeedback(.impact(weight: .heavy), trigger: recorder.isRecording)
            .sensoryFeedback(.success, trigger: recorder.lastSavedTripID)
            .confirmationDialog("停止记录并保存这段行程？", isPresented: $showStopConfirm, titleVisibility: .visible) {
                Button("停止并保存", role: .destructive) {
                    recorder.stopRecording(trigger: .manual)
                }
                Button("继续记录", role: .cancel) {}
            }
            .sheet(isPresented: $showAddVehicle) {
                VehicleEditView(vehicle: nil)
            }
        }
    }

    // MARK: - 没有车辆

    private var addVehiclePrompt: some View {
        VStack(spacing: 14) {
            Image(systemName: "car.side.fill")
                .font(.system(size: 44))
                .foregroundStyle(Theme.brandGradient)
                .padding(.top, 6)
            Text("添加你的第一辆车")
                .font(.title3.weight(.semibold))
            Text("新行程会自动归到「当前车辆」，还可以记录加油、费用和保养。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                showAddVehicle = true
            } label: {
                Label("添加车辆", systemImage: "plus")
                    .font(.headline)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
            }
            .glassButtonStyle(prominent: true)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity)
        .card(padding: 22)
    }

    private func upcomingCard(_ items: [UpcomingItem]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(title: "即将到期", systemImage: "bell.badge.fill", tint: Theme.speed) {
                NavigationLink {
                    MaintenanceListView()
                } label: {
                    HStack(spacing: 2) {
                        Text("保养提醒")
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                    }
                    .font(.subheadline)
                }
            }
            ForEach(items) { item in
                UpcomingRow(item: item)
                if item.id != items.last?.id {
                    Divider().opacity(0.5)
                }
            }
        }
        .card()
    }
}

/// 没在记录时的首页主卡片：当前车辆、里程表、圆形开始按钮
struct IdleHero: View {
    let vehicle: Vehicle
    let vehicles: [Vehicle]
    let odometer: Double
    let onSelectVehicle: (UUID) -> Void
    let onStart: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            HStack(spacing: 12) {
                VehicleAvatar(photoData: vehicle.photoData, size: 52)
                VStack(alignment: .leading, spacing: 2) {
                    Text(vehicle.displayName)
                        .font(.title3.weight(.semibold))
                    Text([vehicle.subtitle, vehicle.plate].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                if vehicles.count > 1 {
                    Menu {
                        ForEach(vehicles) { item in
                            Button {
                                onSelectVehicle(item.id)
                            } label: {
                                if item.id == vehicle.id {
                                    Label(item.displayName, systemImage: "checkmark")
                                } else {
                                    Text(item.displayName)
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.left.arrow.right")
                            .font(.subheadline.weight(.semibold))
                            .frame(width: 36, height: 36)
                            .glassCircle()
                    }
                    .buttonStyle(.plain)
                }
            }

            VStack(spacing: 6) {
                Text("估算里程表")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                OdometerView(value: odometer)
            }

            ZStack {
                // 呼吸光圈
                Circle()
                    .fill(Theme.startButton.opacity(0.25))
                    .frame(width: 112, height: 112)
                    .phaseAnimator([false, true]) { content, expanded in
                        content
                            .scaleEffect(expanded ? 1.35 : 0.9)
                            .opacity(expanded ? 0 : 0.8)
                    } animation: { expanded in
                        expanded ? Animation.easeOut(duration: 2.2) : nil
                    }
                Button(action: onStart) {
                    VStack(spacing: 4) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 28, weight: .bold))
                        Text("START")
                            .font(.system(size: 11, weight: .heavy, design: .rounded))
                            .tracking(1.5)
                    }
                    .foregroundStyle(.white)
                    .frame(width: 84, height: 84)
                }
                .glassButtonStyle(prominent: true)
                .buttonBorderShape(.circle)
                .tint(Theme.startButton)
            }
            .frame(height: 130)

            Text("连上 CarPlay 会自动开始，断开自动保存")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .card(padding: 20)
    }
}

/// 首页概览卡片：当前车辆的本月花费、本月里程、平均油耗
struct VehicleOverviewCard: View {
    let vehicle: Vehicle
    let trips: [Trip]
    let fuel: [FuelEntry]
    let expenses: [Expense]

    var body: some View {
        let summary = OverviewSummary(vehicle: vehicle, trips: trips, fuel: fuel, expenses: expenses, month: Date())
        VStack(alignment: .leading, spacing: 14) {
            CardHeader(title: "本月概览", systemImage: "chart.bar.xaxis", tint: Theme.accent) {
                Text(Fmt.monthTitle.string(from: Date()))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                StatTile(title: "本月花费", value: Fmt.money(summary.monthCost), systemImage: "creditcard.fill", tint: Theme.money)
                StatTile(title: "本月里程", value: Fmt.km(summary.monthKm), systemImage: "road.lanes", tint: Theme.distance)
                StatTile(title: "平均油耗", value: Fmt.economy(summary.averageEconomy), systemImage: "fuelpump.fill", tint: Theme.fuel)
                StatTile(title: "本月行程", value: "\(summary.monthTripCount) 段", systemImage: "map.fill", tint: Theme.altitude)
            }
            NavigationLink {
                StatsView(initialVehicleID: vehicle.id)
            } label: {
                HStack {
                    Label("详细统计", systemImage: "chart.pie.fill")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .glassCapsule(interactive: true)
            }
            .buttonStyle(.plain)
        }
        .card()
    }
}

/// 最近行程：小地图 + 概要
struct LastTripCard: View {
    let trip: Trip
    @State private var segments: [SpeedSegment] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(title: "最近行程", systemImage: "clock.arrow.circlepath", tint: Theme.duration) {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
                if !segments.isEmpty {
                    TripMapView(segments: segments, start: trip.startCoordinate, end: trip.endCoordinate, lineWidth: 4)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            .frame(height: 150)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            TripRow(trip: trip, vehicleName: nil)
        }
        .card()
        .task(id: trip.id) {
            let id = trip.id
            let points = await Task.detached(priority: .utility) {
                TrackStore.readPoints(for: id)
            }.value
            let built = TrackAnalysis.segments(for: points, maxPoints: 800)
            withAnimation(.easeOut(duration: 0.35)) {
                segments = built
            }
        }
    }
}

/// 概览数据（首页、统计页共用）
struct OverviewSummary {
    let odometer: Double
    let monthKm: Double
    let monthTripCount: Int
    let monthCost: Double
    let averageEconomy: Double?

    init(vehicle: Vehicle, trips: [Trip], fuel: [FuelEntry], expenses: [Expense], month: Date) {
        let calendar = Calendar.current
        let vid = vehicle.id
        odometer = OdometerService.estimate(vehicle: vehicle, trips: trips, fuel: fuel, expenses: expenses)

        let monthTrips = trips.filter { $0.vehicleID == vid && calendar.isDate($0.startDate, equalTo: month, toGranularity: .month) }
        monthKm = monthTrips.reduce(0) { $0 + $1.distance } / 1000
        monthTripCount = monthTrips.count

        let fuelCost = fuel
            .filter { $0.vehicleID == vid && calendar.isDate($0.date, equalTo: month, toGranularity: .month) }
            .reduce(0) { $0 + $1.totalCost }
        let otherCost = expenses
            .filter { $0.vehicleID == vid && calendar.isDate($0.date, equalTo: month, toGranularity: .month) }
            .reduce(0) { $0 + $1.amount }
        monthCost = fuelCost + otherCost

        averageEconomy = FuelEconomy.analyze(entries: fuel.filter { $0.vehicleID == vid }).averageEconomy
    }
}
