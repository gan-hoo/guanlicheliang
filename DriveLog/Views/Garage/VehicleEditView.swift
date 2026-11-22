import SwiftUI
import SwiftData

/// 新增 / 编辑车辆
struct VehicleEditView: View {
    let vehicle: Vehicle?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var allVehicles: [Vehicle]

    @State private var nickname: String
    @State private var brand: String
    @State private var modelName: String
    @State private var yearText: String
    @State private var plate: String
    @State private var fuelType: FuelType
    @State private var tankText: String
    @State private var hasPurchaseDate: Bool
    @State private var purchaseDate: Date
    @State private var purchasePriceText: String
    @State private var initialOdometerText: String
    @State private var notes: String
    @State private var photoData: Data?
    @State private var makeCurrent: Bool

    init(vehicle: Vehicle?) {
        self.vehicle = vehicle
        _nickname = State(initialValue: vehicle?.nickname ?? "")
        _brand = State(initialValue: vehicle?.brand ?? "")
        _modelName = State(initialValue: vehicle?.modelName ?? "")
        _yearText = State(initialValue: vehicle?.year.map { String($0) } ?? "")
        _plate = State(initialValue: vehicle?.plate ?? "")
        _fuelType = State(initialValue: vehicle?.fuelType ?? .ulp91)
        _tankText = State(initialValue: Fmt.plain(vehicle?.tankCapacity, decimals: 1))
        _hasPurchaseDate = State(initialValue: vehicle?.purchaseDate != nil)
        _purchaseDate = State(initialValue: vehicle?.purchaseDate ?? Date())
        _purchasePriceText = State(initialValue: Fmt.plain(vehicle?.purchasePrice, decimals: 2))
        _initialOdometerText = State(initialValue: vehicle.map { Fmt.plain($0.initialOdometer, decimals: 0) } ?? "")
        _notes = State(initialValue: vehicle?.notes ?? "")
        _photoData = State(initialValue: vehicle?.photoData)
        _makeCurrent = State(initialValue: vehicle == nil)
    }

    private var isNew: Bool { vehicle == nil }

    private var canSave: Bool {
        !(nickname.trimmingCharacters(in: .whitespaces).isEmpty
          && brand.trimmingCharacters(in: .whitespaces).isEmpty
          && modelName.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    PhotoField(title: "车辆照片", data: $photoData)
                }

                Section("基本信息") {
                    TextField("昵称（例如：小白）", text: $nickname)
                    TextField("品牌（例如：Toyota）", text: $brand)
                    TextField("型号（例如：Corolla）", text: $modelName)
                    NumberField(title: "年份", text: $yearText, placeholder: "2020", keyboard: .numberPad)
                    TextField("车牌", text: $plate)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                }

                Section("燃油") {
                    Picker("燃油类型", selection: $fuelType) {
                        ForEach(FuelType.allCases) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    NumberField(title: "油箱容量", text: $tankText, unit: "L")
                }

                Section("购车") {
                    Toggle("记录购车日期", isOn: $hasPurchaseDate)
                    if hasPurchaseDate {
                        DatePicker("购车日期", selection: $purchaseDate, displayedComponents: .date)
                    }
                    NumberField(title: "购车价格", text: $purchasePriceText, unit: Fmt.currencySymbol, placeholder: "选填")
                }

                Section {
                    NumberField(title: "初始里程表读数", text: $initialOdometerText, unit: "km", keyboard: .numberPad)
                } header: {
                    Text("里程")
                } footer: {
                    Text(isNew
                         ? "填写添加车辆时仪表盘上的里程。之后估算里程 = 最近一次填写的读数 + 之后记录到的行程距离。"
                         : "以后可以在车辆页面随时「校正里程表读数」。")
                }

                Section("备注") {
                    TextField("备注", text: $notes, axis: .vertical)
                        .lineLimit(2...6)
                }

                if isNew {
                    Section {
                        Toggle("设为当前车辆", isOn: $makeCurrent)
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .keyboardDoneToolbar()
            .navigationTitle(isNew ? "添加车辆" : "编辑车辆")
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
        }
    }

    private func save() {
        let target: Vehicle
        let wasEmpty = allVehicles.isEmpty
        if let vehicle {
            target = vehicle
        } else {
            target = Vehicle()
            context.insert(target)
        }
        target.nickname = nickname.trimmingCharacters(in: .whitespaces)
        target.brand = brand.trimmingCharacters(in: .whitespaces)
        target.modelName = modelName.trimmingCharacters(in: .whitespaces)
        target.year = NumberParser.int(yearText)
        target.plate = plate.trimmingCharacters(in: .whitespaces).uppercased()
        target.fuelType = fuelType
        target.tankCapacity = NumberParser.double(tankText)
        target.purchaseDate = hasPurchaseDate ? purchaseDate : nil
        target.purchasePrice = NumberParser.double(purchasePriceText)
        target.initialOdometer = NumberParser.double(initialOdometerText) ?? 0
        target.notes = notes
        target.photoData = photoData
        try? context.save()

        if isNew {
            if makeCurrent || AppSettings.currentVehicleID == nil {
                AppSettings.currentVehicleID = target.id
            }
            if wasEmpty {
                VehicleService.adoptUnassignedTrips(to: target, context: context)
            }
        }
        ReminderEngine.rescheduleAll(context: context)
        dismiss()
    }
}
