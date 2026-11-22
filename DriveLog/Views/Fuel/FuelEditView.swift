import SwiftUI
import SwiftData
import CoreLocation

/// 加油表单：尽量少打字
/// - 里程表默认填估算值，燃油类型默认用车辆设置，单价默认上次同类油价
/// - 加油量 / 单价 / 总价 填任意两个，第三个自动算
/// - 位置默认用当前定位，并列出附近加油站和常用加油站
struct FuelEditView: View {
    let entry: FuelEntry?
    let initialVehicleID: UUID?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Vehicle.createdAt) private var vehicles: [Vehicle]
    @Query(sort: \FuelEntry.date, order: .reverse) private var allEntries: [FuelEntry]
    @Query private var trips: [Trip]
    @Query private var expenses: [Expense]

    private enum Field: Hashable {
        case liters, price, total
    }

    @State private var vehicleID: UUID?
    @State private var date = Date()
    @State private var odometerText = ""
    @State private var litersText = ""
    @State private var priceText = ""
    @State private var totalText = ""
    @State private var fuelType: FuelType = .ulp91
    @State private var stationName = ""
    @State private var latitude: Double?
    @State private var longitude: Double?
    @State private var isFullTank = true
    @State private var missedPrevious = false
    @State private var notes = ""
    @State private var editOrder: [Field] = []
    @State private var nearbyStations: [String] = []
    @State private var locating = false
    @State private var didLoad = false
    @State private var locator = OneShotLocation()

    init(entry: FuelEntry?, vehicleID: UUID?) {
        self.entry = entry
        self.initialVehicleID = vehicleID
    }

    private var isNew: Bool { entry == nil }

    private var canSave: Bool {
        vehicleID != nil
            && (NumberParser.double(litersText) ?? 0) > 0
            && (NumberParser.double(totalText) ?? 0) > 0
            && NumberParser.double(odometerText) != nil
    }

    private var stationSuggestions: [String] {
        var counts: [String: Int] = [:]
        for e in allEntries where !e.stationName.isEmpty {
            counts[e.stationName, default: 0] += 1
        }
        let history = counts.sorted { $0.value > $1.value }.map(\.key)
        var result: [String] = []
        for name in nearbyStations + history where !result.contains(name) {
            if stationName.isEmpty || name.localizedCaseInsensitiveContains(stationName) {
                if name != stationName { result.append(name) }
            }
        }
        return Array(result.prefix(8))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("车辆", selection: $vehicleID) {
                        ForEach(vehicles) { v in
                            Text(v.displayName).tag(UUID?.some(v.id))
                        }
                    }
                    DatePicker("时间", selection: $date)
                    NumberField(title: "里程表", text: $odometerText, unit: "km", keyboard: .numberPad)
                }

                Section {
                    NumberField(title: "加油量", text: binding(for: .liters), unit: "L")
                    NumberField(title: "单价", text: binding(for: .price), unit: "\(Fmt.currencySymbol)/L")
                    NumberField(title: "总价", text: binding(for: .total), unit: Fmt.currencySymbol)
                    Picker("燃油类型", selection: $fuelType) {
                        ForEach(FuelType.allCases) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("加油")
                } footer: {
                    Text("加油量、单价、总价填任意两个，第三个自动计算。")
                }

                Section("加油站") {
                    TextField("加油站名称", text: $stationName)
                    SuggestionChips(suggestions: stationSuggestions) { name in
                        stationName = name
                    }
                    HStack {
                        if locating {
                            ProgressView()
                            Text("正在获取当前位置…")
                                .foregroundStyle(.secondary)
                        } else if let latitude, let longitude {
                            Image(systemName: "location.fill")
                                .foregroundStyle(.blue)
                            Text(String(format: "%.5f, %.5f", latitude, longitude))
                                .font(.footnote.monospacedDigit())
                                .foregroundStyle(.secondary)
                        } else {
                            Image(systemName: "location.slash")
                                .foregroundStyle(.secondary)
                            Text("未记录位置")
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(latitude == nil ? "定位" : "重新定位") {
                            Task { await locate() }
                        }
                        .disabled(locating)
                    }
                    if latitude != nil {
                        Button("清除位置", role: .destructive) {
                            latitude = nil
                            longitude = nil
                        }
                    }
                }

                Section {
                    Toggle("加满了", isOn: $isFullTank)
                    Toggle("上次加油漏记了", isOn: $missedPrevious)
                } footer: {
                    Text("油耗按「满箱到满箱」计算。忘了记录上一次加油时打开「上次加油漏记了」，这一段就不计入油耗。")
                }

                Section("备注") {
                    TextField("备注", text: $notes, axis: .vertical)
                        .lineLimit(1...4)
                }

                if !isNew {
                    Section {
                        Button("删除这条记录", role: .destructive) {
                            if let entry {
                                context.delete(entry)
                                try? context.save()
                            }
                            dismiss()
                        }
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .keyboardDoneToolbar()
            .navigationTitle(isNew ? "记录加油" : "编辑加油")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(!canSave)
                }
            }
            .onAppear(perform: loadIfNeeded)
            .onChange(of: vehicleID) { oldValue, newValue in
                guard isNew, didLoad, oldValue != newValue else { return }
                applyVehicleDefaults()
            }
        }
    }

    // MARK: - 三选二自动计算

    private func binding(for field: Field) -> Binding<String> {
        Binding(
            get: {
                switch field {
                case .liters: return litersText
                case .price: return priceText
                case .total: return totalText
                }
            },
            set: { newValue in
                switch field {
                case .liters: litersText = newValue
                case .price: priceText = newValue
                case .total: totalText = newValue
                }
                userEdited(field)
            }
        )
    }

    private func userEdited(_ field: Field) {
        editOrder.removeAll { $0 == field }
        editOrder.append(field)
        recompute()
    }

    /// 最近编辑的两个字段作为输入，算出剩下那个
    private func recompute() {
        let all: [Field] = [.liters, .price, .total]
        var inputs = Array(editOrder.suffix(2))
        // 只编辑过一个字段时，把另一个已有值的字段当作输入（例如默认带出的单价）
        if inputs.count < 2 {
            for f in all where !inputs.contains(f) && value(of: f) != nil {
                inputs.insert(f, at: 0)
                if inputs.count == 2 { break }
            }
        }
        guard inputs.count == 2, let target = all.first(where: { !inputs.contains($0) }) else { return }
        let liters = value(of: .liters)
        let price = value(of: .price)
        let total = value(of: .total)
        switch target {
        case .total:
            if let liters, let price { totalText = Fmt.plain(liters * price, decimals: 2) }
        case .liters:
            if let total, let price, price > 0 { litersText = Fmt.plain(total / price, decimals: 2) }
        case .price:
            if let total, let liters, liters > 0 { priceText = Fmt.plain(total / liters, decimals: 3) }
        }
    }

    private func value(of field: Field) -> Double? {
        switch field {
        case .liters: return NumberParser.double(litersText)
        case .price: return NumberParser.double(priceText)
        case .total: return NumberParser.double(totalText)
        }
    }

    // MARK: - 默认值

    private func loadIfNeeded() {
        guard !didLoad else { return }
        if let entry {
            vehicleID = entry.vehicleID
            date = entry.date
            odometerText = Fmt.plain(entry.odometer, decimals: 0)
            litersText = Fmt.plain(entry.liters, decimals: 2)
            priceText = Fmt.plain(entry.pricePerLiter, decimals: 3)
            totalText = Fmt.plain(entry.totalCost, decimals: 2)
            fuelType = entry.fuelType
            stationName = entry.stationName
            latitude = entry.latitude
            longitude = entry.longitude
            isFullTank = entry.isFullTank
            missedPrevious = entry.missedPrevious
            notes = entry.notes
            // 编辑已有记录：改加油量或单价 → 重算总价；改总价 → 重算单价
            editOrder = [.price, .liters]
            didLoad = true
        } else {
            vehicleID = initialVehicleID ?? vehicles.first?.id
            applyVehicleDefaults()
            didLoad = true
            Task { await locate() }
        }
    }

    private func applyVehicleDefaults() {
        guard let vehicle = vehicles.first(where: { $0.id == vehicleID }) else { return }
        let estimate = OdometerService.estimate(vehicle: vehicle, trips: trips, fuel: allEntries, expenses: expenses)
        odometerText = Fmt.plain(estimate.rounded(), decimals: 0)
        fuelType = vehicle.fuelType
        if let last = allEntries.first(where: { $0.fuelTypeRaw == vehicle.fuelTypeRaw && $0.pricePerLiter > 0 }) {
            priceText = Fmt.plain(last.pricePerLiter, decimals: 3)
        }
    }

    private func locate() async {
        locating = true
        defer { locating = false }
        guard let location = await locator.fetch() else { return }
        latitude = location.coordinate.latitude
        longitude = location.coordinate.longitude
        let names = await NearbyPlaces.gasStations(near: location.coordinate)
        nearbyStations = names
        if isNew, stationName.isEmpty, let first = names.first {
            stationName = first
        }
    }

    // MARK: - 保存

    private func save() {
        guard let liters = NumberParser.double(litersText),
              let total = NumberParser.double(totalText),
              let odometer = NumberParser.double(odometerText) else { return }
        let target: FuelEntry
        if let entry {
            target = entry
        } else {
            target = FuelEntry(vehicleID: vehicleID, date: date)
            context.insert(target)
        }
        target.vehicleID = vehicleID
        target.date = date
        target.odometer = odometer
        target.liters = liters
        target.totalCost = total
        target.pricePerLiter = NumberParser.double(priceText) ?? (liters > 0 ? total / liters : 0)
        target.fuelType = fuelType
        target.stationName = stationName.trimmingCharacters(in: .whitespaces)
        target.latitude = latitude
        target.longitude = longitude
        target.isFullTank = isFullTank
        target.missedPrevious = missedPrevious
        target.notes = notes
        try? context.save()
        ReminderEngine.checkMileageReminders(context: context)
        dismiss()
    }
}
