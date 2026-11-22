import SwiftUI
import SwiftData

/// 保养提醒列表：按日期或按里程（例如每 10,000 km 或每 12 个月）
struct MaintenanceListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \MaintenanceReminder.title) private var reminders: [MaintenanceReminder]
    @Query(sort: \Vehicle.createdAt) private var vehicles: [Vehicle]
    @Query private var trips: [Trip]
    @Query private var fuelEntries: [FuelEntry]
    @Query private var expenses: [Expense]
    @AppStorage(AppSettings.currentVehicleKey) private var currentVehicleIDString: String = ""

    @State private var editing: MaintenanceReminder?
    @State private var showAdd = false
    @State private var completing: MaintenanceReminder?

    var body: some View {
        List {
            if vehicles.isEmpty {
                ContentUnavailableView("先添加一辆车", systemImage: "car")
            }
            ForEach(vehicles) { vehicle in
                let items = reminders.filter { $0.vehicleID == vehicle.id }
                if !items.isEmpty {
                    Section(vehicle.displayName) {
                        ForEach(items) { reminder in
                            let status = MaintenanceStatus(reminder: reminder, vehicle: vehicle, trips: trips,
                                                           fuel: fuelEntries, expenses: expenses)
                            Button {
                                editing = reminder
                            } label: {
                                MaintenanceRow(reminder: reminder, status: status)
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .leading) {
                                Button {
                                    completing = reminder
                                } label: {
                                    Label("已完成", systemImage: "checkmark")
                                }
                                .tint(.green)
                            }
                        }
                        .onDelete { offsets in
                            for index in offsets {
                                context.delete(items[index])
                            }
                            try? context.save()
                            ReminderEngine.rescheduleAll(context: context)
                        }
                    }
                }
            }
            if !vehicles.isEmpty && reminders.isEmpty {
                Section {
                    Text("还没有保养提醒。点右上角「+」添加，例如「更换机油：每 10,000 km 或每 12 个月」。")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("保养提醒")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAdd = true
                } label: {
                    Image(systemName: "plus")
                }
                .disabled(vehicles.isEmpty)
            }
        }
        .sheet(isPresented: $showAdd) {
            MaintenanceEditView(reminder: nil, defaultVehicleID: UUID(uuidString: currentVehicleIDString) ?? vehicles.first?.id)
        }
        .sheet(item: $editing) { reminder in
            MaintenanceEditView(reminder: reminder, defaultVehicleID: reminder.vehicleID)
        }
        .confirmationDialog("「\(completing?.title ?? "")」已完成？",
                            isPresented: Binding(get: { completing != nil }, set: { if !$0 { completing = nil } }),
                            titleVisibility: .visible) {
            Button("标记已完成（从今天和当前估算里程重新计算）") {
                if let reminder = completing {
                    markDone(reminder)
                }
                completing = nil
            }
            Button("取消", role: .cancel) { completing = nil }
        }
    }

    private func markDone(_ reminder: MaintenanceReminder) {
        reminder.lastDoneDate = Date()
        if let vehicle = vehicles.first(where: { $0.id == reminder.vehicleID }) {
            reminder.lastDoneOdometer = OdometerService.estimate(vehicle: vehicle, trips: trips, fuel: fuelEntries, expenses: expenses).rounded()
        }
        reminder.notifiedDueOdometer = nil
        try? context.save()
        ReminderEngine.rescheduleAll(context: context)
    }
}

struct MaintenanceRow: View {
    let reminder: MaintenanceReminder
    let status: MaintenanceStatus

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "wrench.and.screwdriver.fill")
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(RoundedRectangle(cornerRadius: 9).fill(color))
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(reminder.title)
                        .font(.headline)
                    if !reminder.isEnabled {
                        Text("已暂停")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(intervalText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(status.summary)
                    .font(.subheadline)
                    .foregroundStyle(status.isOverdue ? Color.red : (status.isDueSoon ? Color.orange : Color.secondary))
            }
            Spacer()
        }
        .contentShape(Rectangle())
    }

    private var color: Color {
        if !reminder.isEnabled { return .gray }
        if status.isOverdue { return .red }
        if status.isDueSoon { return .orange }
        return .green
    }

    private var intervalText: String {
        var parts: [String] = []
        if let km = reminder.intervalKm, km > 0 { parts.append("每 \(Fmt.odometer(km))") }
        if let months = reminder.intervalMonths, months > 0 { parts.append("每 \(months) 个月") }
        let last = "上次 \(Fmt.dateFull.string(from: reminder.lastDoneDate))"
            + (reminder.lastDoneOdometer.map { " · \(Fmt.odometer($0))" } ?? "")
        return (parts.isEmpty ? "" : parts.joined(separator: " 或 ") + " · ") + last
    }
}

struct MaintenanceEditView: View {
    let reminder: MaintenanceReminder?
    let defaultVehicleID: UUID?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Vehicle.createdAt) private var vehicles: [Vehicle]
    @Query private var trips: [Trip]
    @Query private var fuelEntries: [FuelEntry]
    @Query private var expenses: [Expense]

    @State private var vehicleID: UUID?
    @State private var title = ""
    @State private var intervalKmText = ""
    @State private var intervalMonthsText = ""
    @State private var lastDoneDate = Date()
    @State private var lastDoneOdometerText = ""
    @State private var isEnabled = true
    @State private var notes = ""
    @State private var didLoad = false

    static let presets: [(title: String, km: Int, months: Int)] = [
        ("更换机油", 10000, 12),
        ("常规保养", 15000, 12),
        ("轮胎换位", 10000, 0),
        ("空调滤芯", 20000, 12),
        ("刹车油", 0, 24),
        ("火花塞", 60000, 0)
    ]

    var body: some View {
        NavigationStack {
            Form {
                if reminder == nil {
                    Section("常用") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(Self.presets.indices, id: \.self) { index in
                                    let preset = Self.presets[index]
                                    Button(preset.title) {
                                        title = preset.title
                                        intervalKmText = preset.km > 0 ? "\(preset.km)" : ""
                                        intervalMonthsText = preset.months > 0 ? "\(preset.months)" : ""
                                    }
                                    .glassButtonStyle()
                                }
                            }
                        }
                    }
                }

                Section {
                    TextField("项目（例如：更换机油）", text: $title)
                    Picker("车辆", selection: $vehicleID) {
                        ForEach(vehicles) { v in
                            Text(v.displayName).tag(UUID?.some(v.id))
                        }
                    }
                    Toggle("启用提醒", isOn: $isEnabled)
                }

                Section {
                    NumberField(title: "每隔", text: $intervalKmText, unit: "km", placeholder: "不按里程", keyboard: .numberPad)
                    NumberField(title: "每隔", text: $intervalMonthsText, unit: "个月", placeholder: "不按日期", keyboard: .numberPad)
                } header: {
                    Text("间隔（任一到期即提醒）")
                } footer: {
                    Text("按里程：估算里程距离到期不足 300 km 时提醒一次。按日期：到期前 7 天和当天 09:00 提醒。")
                }

                Section("上次完成") {
                    DatePicker("日期", selection: $lastDoneDate, in: ...Date(), displayedComponents: .date)
                    HStack {
                        NumberField(title: "里程表", text: $lastDoneOdometerText, unit: "km", keyboard: .numberPad)
                        Button("估算") {
                            if let vehicle = vehicles.first(where: { $0.id == vehicleID }) {
                                let estimate = OdometerService.estimate(vehicle: vehicle, trips: trips, fuel: fuelEntries, expenses: expenses)
                                lastDoneOdometerText = Fmt.plain(estimate.rounded(), decimals: 0)
                            }
                        }
                        .glassButtonStyle()
                        .controlSize(.small)
                    }
                }

                Section("备注") {
                    TextField("备注", text: $notes, axis: .vertical)
                        .lineLimit(1...4)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .keyboardDoneToolbar()
            .navigationTitle(reminder == nil ? "新建保养提醒" : "编辑保养提醒")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || vehicleID == nil
                                  || (NumberParser.double(intervalKmText) == nil && NumberParser.int(intervalMonthsText) == nil))
                }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        if let reminder {
            vehicleID = reminder.vehicleID
            title = reminder.title
            intervalKmText = Fmt.plain(reminder.intervalKm, decimals: 0)
            intervalMonthsText = reminder.intervalMonths.map { "\($0)" } ?? ""
            lastDoneDate = reminder.lastDoneDate
            lastDoneOdometerText = Fmt.plain(reminder.lastDoneOdometer, decimals: 0)
            isEnabled = reminder.isEnabled
            notes = reminder.notes
        } else {
            vehicleID = defaultVehicleID ?? vehicles.first?.id
            if let vehicle = vehicles.first(where: { $0.id == vehicleID }) {
                let estimate = OdometerService.estimate(vehicle: vehicle, trips: trips, fuel: fuelEntries, expenses: expenses)
                lastDoneOdometerText = Fmt.plain(estimate.rounded(), decimals: 0)
            }
        }
    }

    private func save() {
        let target: MaintenanceReminder
        if let reminder {
            target = reminder
        } else {
            target = MaintenanceReminder(vehicleID: vehicleID, title: title)
            context.insert(target)
        }
        let oldDueOdometer = target.dueOdometer
        target.vehicleID = vehicleID
        target.title = title.trimmingCharacters(in: .whitespaces)
        let km = NumberParser.double(intervalKmText)
        target.intervalKm = (km ?? 0) > 0 ? km : nil
        let months = NumberParser.int(intervalMonthsText)
        target.intervalMonths = (months ?? 0) > 0 ? months : nil
        target.lastDoneDate = lastDoneDate
        target.lastDoneOdometer = NumberParser.double(lastDoneOdometerText)
        target.isEnabled = isEnabled
        target.notes = notes
        if target.dueOdometer != oldDueOdometer {
            target.notifiedDueOdometer = nil
        }
        try? context.save()
        ReminderEngine.rescheduleAll(context: context)
        dismiss()
    }
}
