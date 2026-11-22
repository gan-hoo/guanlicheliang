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
            ScrollView {
                VStack(spacing: 16) {
                    PermissionBanner()

                    if recorder.isRecording {
                        RecordingPanel(recorder: recorder, vehicleName: recordingVehicleName) {
                            showStopConfirm = true
                        }
                    } else {
                        idlePanel
                    }

                    if let vehicle = currentVehicle {
                        VehicleOverviewCard(vehicle: vehicle, trips: trips, fuel: fuelEntries, expenses: expenses)
                    } else {
                        addVehiclePrompt
                    }

                    let upcoming = ReminderEngine.upcomingItems(expenses: expenses, reminders: reminders,
                                                                categories: categories, vehicles: vehicles,
                                                                trips: trips, fuel: fuelEntries)
                    if !upcoming.isEmpty {
                        upcomingCard(Array(upcoming.prefix(4)))
                    }

                    if let last = trips.first {
                        NavigationLink {
                            TripDetailView(trip: last)
                        } label: {
                            lastTripCard(last)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background { AppBackground() }
            .navigationTitle("行车记录")
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

    // MARK: - 没在记录

    private var idlePanel: some View {
        VStack(spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("未在记录")
                        .font(.headline)
                    Text("连上 CarPlay 时快捷指令会自动开始，也可以手动开始。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            if vehicles.count > 1 {
                Menu {
                    ForEach(vehicles) { vehicle in
                        Button {
                            currentVehicleIDString = vehicle.id.uuidString
                        } label: {
                            if vehicle.id == currentVehicle?.id {
                                Label(vehicle.displayName, systemImage: "checkmark")
                            } else {
                                Text(vehicle.displayName)
                            }
                        }
                    }
                } label: {
                    HStack {
                        Image(systemName: "car.fill")
                        Text("当前车辆：\(currentVehicle?.displayName ?? "未选择")")
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .glassCapsule(interactive: true)
                }
                .buttonStyle(.plain)
            }

            Button {
                recorder.startRecording(trigger: .manual)
            } label: {
                Label("开始记录", systemImage: "play.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .glassButtonStyle(prominent: true)
            .controlSize(.large)
        }
        .card()
    }

    private var addVehiclePrompt: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("还没有车辆", systemImage: "car.badge.gearshape")
                .font(.headline)
            Text("添加车辆后，新行程会自动归到「当前车辆」，并可以记录加油和费用。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button {
                showAddVehicle = true
            } label: {
                Label("添加车辆", systemImage: "plus")
            }
            .glassButtonStyle(prominent: true)
        }
        .card()
    }

    private func upcomingCard(_ items: [UpcomingItem]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("即将到期")
                    .font(.headline)
                Spacer()
                NavigationLink {
                    MaintenanceListView()
                } label: {
                    Text("保养提醒")
                        .font(.subheadline)
                }
            }
            ForEach(items) { item in
                UpcomingRow(item: item)
            }
        }
        .card()
    }

    private func lastTripCard(_ trip: Trip) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("最近行程")
                    .font(.headline)
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
            }
            TripRow(trip: trip, vehicleName: nil)
        }
        .card()
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
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                VehicleAvatar(photoData: vehicle.photoData, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(vehicle.displayName)
                        .font(.headline)
                    Text("估算里程 \(Fmt.odometer(summary.odometer))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(Fmt.monthTitle.string(from: Date()))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                StatTile(title: "本月花费", value: Fmt.money(summary.monthCost), systemImage: "creditcard.fill", tint: .pink)
                StatTile(title: "本月里程", value: Fmt.km(summary.monthKm), systemImage: "road.lanes", tint: .blue)
                StatTile(title: "平均油耗", value: Fmt.economy(summary.averageEconomy), systemImage: "fuelpump.fill", tint: .orange)
                StatTile(title: "本月行程", value: "\(summary.monthTripCount) 段", systemImage: "map.fill", tint: .green)
            }
            NavigationLink {
                StatsView(initialVehicleID: vehicle.id)
            } label: {
                HStack {
                    Image(systemName: "chart.pie.fill")
                    Text("查看详细统计")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.tertiary)
                }
                .font(.subheadline)
            }
        }
        .card()
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
