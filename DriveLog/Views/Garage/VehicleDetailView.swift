import SwiftUI
import SwiftData

struct VehicleDetailView: View {
    @Bindable var vehicle: Vehicle
    @Query private var trips: [Trip]
    @Query private var fuelEntries: [FuelEntry]
    @Query private var expenses: [Expense]
    @AppStorage(AppSettings.currentVehicleKey) private var currentVehicleIDString: String = ""

    @State private var showEdit = false
    @State private var showCalibrate = false

    private var vehicleTrips: [Trip] { trips.filter { $0.vehicleID == vehicle.id } }
    private var vehicleFuel: [FuelEntry] { fuelEntries.filter { $0.vehicleID == vehicle.id } }
    private var vehicleExpenses: [Expense] { expenses.filter { $0.vehicleID == vehicle.id } }

    var body: some View {
        let reading = OdometerService.latestReading(vehicle: vehicle, fuel: fuelEntries, expenses: expenses)
        let addedKm = OdometerService.tripKilometers(after: reading.date, vehicleID: vehicle.id, trips: trips)
        let estimate = reading.value + addedKm
        let analysis = FuelEconomy.analyze(entries: vehicleFuel)

        List {
            Section {
                HStack(spacing: 16) {
                    VehicleAvatar(photoData: vehicle.photoData, size: 72)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(vehicle.displayName)
                            .font(.title2.weight(.bold))
                        if !vehicle.subtitle.isEmpty {
                            Text(vehicle.subtitle)
                                .foregroundStyle(.secondary)
                        }
                        if !vehicle.plate.isEmpty {
                            Text(vehicle.plate)
                                .font(.subheadline.monospaced())
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary, lineWidth: 1))
                        }
                    }
                }
                .padding(.vertical, 4)

                if vehicle.id.uuidString == currentVehicleIDString {
                    Label("这是当前车辆，新行程会自动归到这辆车", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.subheadline)
                } else {
                    Button {
                        currentVehicleIDString = vehicle.id.uuidString
                    } label: {
                        Label("设为当前车辆", systemImage: "checkmark.circle")
                    }
                }
            }

            Section {
                VStack(spacing: 8) {
                    Text("估算当前里程")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    OdometerView(value: estimate, digits: 6, digitWidth: 24, digitHeight: 36)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                Button {
                    showCalibrate = true
                } label: {
                    Label("校正里程表读数", systemImage: "gauge.with.needle")
                }
            } header: {
                Text("里程")
            } footer: {
                Text("依据：\(reading.source) \(Fmt.odometer(reading.value))（\(Fmt.dateTimeShort.string(from: reading.date))）+ 之后记录的行程 \(Fmt.km(addedKm))")
            }

            Section("统计") {
                InfoRow(title: "记录的行程", value: "\(vehicleTrips.count) 段 · \(Fmt.km(vehicleTrips.reduce(0) { $0 + $1.distance } / 1000))")
                InfoRow(title: "加油次数", value: "\(vehicleFuel.count) 次")
                InfoRow(title: "平均油耗", value: Fmt.economy(analysis.averageEconomy))
                InfoRow(title: "油费合计", value: Fmt.money(vehicleFuel.reduce(0) { $0 + $1.totalCost }))
                InfoRow(title: "其他费用合计", value: Fmt.money(vehicleExpenses.reduce(0) { $0 + $1.amount }))
                NavigationLink {
                    StatsView(initialVehicleID: vehicle.id)
                } label: {
                    Label("详细统计", systemImage: "chart.pie")
                }
            }

            Section("信息") {
                InfoRow(title: "品牌", value: vehicle.brand.isEmpty ? "—" : vehicle.brand)
                InfoRow(title: "型号", value: vehicle.modelName.isEmpty ? "—" : vehicle.modelName)
                InfoRow(title: "年份", value: vehicle.year.map { "\($0)" } ?? "—")
                InfoRow(title: "车牌", value: vehicle.plate.isEmpty ? "—" : vehicle.plate)
                InfoRow(title: "燃油类型", value: vehicle.fuelType.displayName)
                InfoRow(title: "油箱容量", value: vehicle.tankCapacity.map { "\(Fmt.number($0, decimals: 0)) L" } ?? "—")
                InfoRow(title: "购车日期", value: vehicle.purchaseDate.map { Fmt.dateFull.string(from: $0) } ?? "—")
                InfoRow(title: "购车价格", value: vehicle.purchasePrice.map { Fmt.money($0) } ?? "—")
                InfoRow(title: "初始里程", value: Fmt.odometer(vehicle.initialOdometer))
                if !vehicle.notes.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("备注")
                        Text(vehicle.notes)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .appBackground()
        .navigationTitle(vehicle.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("编辑") { showEdit = true }
            }
        }
        .sheet(isPresented: $showEdit) {
            VehicleEditView(vehicle: vehicle)
        }
        .sheet(isPresented: $showCalibrate) {
            OdometerCalibrationSheet(vehicle: vehicle, estimate: estimate)
        }
    }
}

/// 手动校正里程表读数
struct OdometerCalibrationSheet: View {
    let vehicle: Vehicle
    let estimate: Double
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var valueText = ""
    @State private var date = Date()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NumberField(title: "里程表读数", text: $valueText, unit: "km", keyboard: .numberPad)
                    DatePicker("读数时间", selection: $date, in: ...Date())
                } footer: {
                    Text("当前估算值 \(Fmt.odometer(estimate))。校正后，估算 = 这次读数 + 之后记录到的行程距离。")
                }
            }
            .navigationTitle("校正里程")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        if let value = NumberParser.double(valueText) {
                            vehicle.odometerCalibration = value
                            vehicle.odometerCalibrationDate = date
                            try? context.save()
                            ReminderEngine.rescheduleAll(context: context)
                        }
                        dismiss()
                    }
                    .disabled(NumberParser.double(valueText) == nil)
                }
            }
            .onAppear {
                valueText = String(Int(estimate.rounded()))
            }
        }
        .presentationDetents([.medium])
    }
}
