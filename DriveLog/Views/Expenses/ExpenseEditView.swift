import SwiftUI
import SwiftData

/// 新增 / 编辑 / 续费 一条费用
struct ExpenseEditView: View {
    let expense: Expense?
    let defaultVehicleID: UUID?
    /// 续费：以旧记录为模板新建一期，保存后旧记录标记为「已续费」
    let renewing: Expense?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Vehicle.createdAt) private var vehicles: [Vehicle]
    @Query(sort: \ExpenseCategory.sortOrder) private var categories: [ExpenseCategory]
    @Query(sort: \Expense.date, order: .reverse) private var allExpenses: [Expense]
    @Query private var trips: [Trip]
    @Query private var fuelEntries: [FuelEntry]

    @State private var vehicleID: UUID?
    @State private var categoryID: UUID?
    @State private var date = Date()
    @State private var amountText = ""
    @State private var odometerText = ""
    @State private var merchant = ""
    @State private var notes = ""
    @State private var receiptData: Data?
    @State private var recurrenceMonths = 0
    @State private var dueDate = Date()
    @State private var reminderEnabled = true
    @State private var remindDaysBefore = 14
    @State private var renewed = false
    @State private var didLoad = false
    @State private var userTouchedRecurrence = false
    @FocusState private var amountFocused: Bool

    struct RecurrenceOption: Hashable {
        let months: Int
        let label: String
    }

    static let recurrenceOptions: [RecurrenceOption] = [
        RecurrenceOption(months: 0, label: "不重复"),
        RecurrenceOption(months: 1, label: "每月"),
        RecurrenceOption(months: 3, label: "每 3 个月"),
        RecurrenceOption(months: 6, label: "每 6 个月"),
        RecurrenceOption(months: 12, label: "每年"),
        RecurrenceOption(months: 24, label: "每 2 年")
    ]
    static let remindOptions = [3, 7, 14, 30, 60]

    init(expense: Expense?, defaultVehicleID: UUID?, renewing: Expense? = nil) {
        self.expense = expense
        self.defaultVehicleID = defaultVehicleID
        self.renewing = renewing
    }

    private var isNew: Bool { expense == nil }

    private var canSave: Bool {
        vehicleID != nil && (NumberParser.double(amountText) ?? 0) > 0
    }

    private var title: String {
        if renewing != nil { return "续费" }
        return isNew ? "记录费用" : "编辑费用"
    }

    /// 常用商家：同分类优先，按使用次数排序
    private var merchantSuggestions: [String] {
        var sameCategory: [String: Int] = [:]
        var others: [String: Int] = [:]
        for e in allExpenses where !e.merchant.isEmpty {
            if e.categoryID == categoryID {
                sameCategory[e.merchant, default: 0] += 1
            } else {
                others[e.merchant, default: 0] += 1
            }
        }
        let ordered = sameCategory.sorted { $0.value > $1.value }.map(\.key)
            + others.sorted { $0.value > $1.value }.map(\.key)
        var result: [String] = []
        for name in ordered where !result.contains(name) && name != merchant {
            if merchant.isEmpty || name.localizedCaseInsensitiveContains(merchant) {
                result.append(name)
            }
        }
        return Array(result.prefix(8))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text(Fmt.currencySymbol)
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        TextField("金额", text: $amountText)
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .keyboardType(.decimalPad)
                            .focused($amountFocused)
                    }
                }

                Section("分类") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 8)], spacing: 8) {
                        ForEach(categories) { category in
                            Button {
                                categoryID = category.id
                                applyCategoryDefaults(category)
                            } label: {
                                VStack(spacing: 4) {
                                    CategoryIcon(iconName: category.iconName, color: CategoryPalette.color(for: category), size: 30)
                                    Text(category.name)
                                        .font(.caption2)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.7)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(categoryID == category.id ? Color.accentColor.opacity(0.18) : Color.clear)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(categoryID == category.id ? Color.accentColor : Color.clear, lineWidth: 1.5)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    Picker("车辆", selection: $vehicleID) {
                        ForEach(vehicles) { v in
                            Text(v.displayName).tag(UUID?.some(v.id))
                        }
                    }
                    DatePicker("日期", selection: $date, displayedComponents: .date)
                    TextField("商家（选填）", text: $merchant)
                    SuggestionChips(suggestions: merchantSuggestions) { name in
                        merchant = name
                    }
                    HStack {
                        NumberField(title: "里程表", text: $odometerText, unit: "km", placeholder: "选填", keyboard: .numberPad)
                        Button("估算") {
                            fillEstimatedOdometer()
                        }
                        .glassButtonStyle()
                        .controlSize(.small)
                    }
                }

                Section {
                    Picker("周期", selection: Binding(
                        get: { recurrenceMonths },
                        set: { newValue in
                            userTouchedRecurrence = true
                            recurrenceMonths = newValue
                            updateDueDate()
                        })) {
                        ForEach(Self.recurrenceOptions, id: \.months) { option in
                            Text(option.label).tag(option.months)
                        }
                    }
                    if recurrenceMonths > 0 {
                        DatePicker("下次到期日", selection: $dueDate, displayedComponents: .date)
                        Toggle("到期前提醒", isOn: $reminderEnabled)
                        if reminderEnabled {
                            Picker("提前", selection: $remindDaysBefore) {
                                ForEach(Self.remindOptions, id: \.self) { days in
                                    Text("\(days) 天").tag(days)
                                }
                            }
                        }
                        if !isNew {
                            Toggle("已续费（不再提醒）", isOn: $renewed)
                        }
                    }
                } header: {
                    Text("周期性费用")
                } footer: {
                    Text("例如保险、注册费（rego）每年一次：设好到期日，到期前会收到本地通知。续费时在费用列表里左滑或点「续费」，自动生成下一期。")
                }

                Section("收据 / 备注") {
                    PhotoField(title: "收据照片", data: $receiptData)
                    TextField("备注", text: $notes, axis: .vertical)
                        .lineLimit(1...4)
                }

                if !isNew {
                    Section {
                        Button("删除这条记录", role: .destructive) {
                            if let expense {
                                context.delete(expense)
                                try? context.save()
                                ReminderEngine.rescheduleAll(context: context)
                            }
                            dismiss()
                        }
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .keyboardDoneToolbar()
            .navigationTitle(title)
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
            .onAppear(perform: load)
            .onChange(of: date) { _, _ in
                if isNew { updateDueDate() }
            }
        }
    }

    // MARK: -

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        if let expense {
            vehicleID = expense.vehicleID
            categoryID = expense.categoryID
            date = expense.date
            amountText = Fmt.plain(expense.amount, decimals: 2)
            odometerText = Fmt.plain(expense.odometer, decimals: 0)
            merchant = expense.merchant
            notes = expense.notes
            receiptData = expense.receiptData
            recurrenceMonths = expense.recurrenceMonths
            dueDate = expense.dueDate ?? Date()
            reminderEnabled = expense.reminderEnabled
            remindDaysBefore = expense.remindDaysBefore
            renewed = expense.renewed
            userTouchedRecurrence = true
        } else if let renewing {
            vehicleID = renewing.vehicleID
            categoryID = renewing.categoryID
            date = Date()
            amountText = Fmt.plain(renewing.amount, decimals: 2)
            merchant = renewing.merchant
            recurrenceMonths = max(renewing.recurrenceMonths, 1)
            reminderEnabled = renewing.reminderEnabled
            remindDaysBefore = renewing.remindDaysBefore
            let base = renewing.dueDate ?? Date()
            dueDate = Calendar.current.date(byAdding: .month, value: recurrenceMonths, to: base) ?? base
            userTouchedRecurrence = true
        } else {
            vehicleID = defaultVehicleID ?? vehicles.first?.id
            categoryID = categories.first?.id
            amountFocused = true
        }
    }

    /// 保险、注册费、年检默认每年一次
    private func applyCategoryDefaults(_ category: ExpenseCategory) {
        guard isNew, renewing == nil, !userTouchedRecurrence else { return }
        let yearly = ["保险", "注册", "rego", "年检"]
        recurrenceMonths = yearly.contains(where: { category.name.localizedCaseInsensitiveContains($0) }) ? 12 : 0
        updateDueDate()
    }

    private func updateDueDate() {
        guard recurrenceMonths > 0, renewing == nil || !isNew else { return }
        if isNew {
            dueDate = Calendar.current.date(byAdding: .month, value: recurrenceMonths, to: date) ?? date
        }
    }

    private func fillEstimatedOdometer() {
        guard let vehicle = vehicles.first(where: { $0.id == vehicleID }) else { return }
        let estimate = OdometerService.estimate(vehicle: vehicle, trips: trips, fuel: fuelEntries, expenses: allExpenses)
        odometerText = Fmt.plain(estimate.rounded(), decimals: 0)
    }

    private func save() {
        guard let amount = NumberParser.double(amountText) else { return }
        let target: Expense
        if let expense {
            target = expense
        } else {
            target = Expense(vehicleID: vehicleID, categoryID: categoryID, date: date, amount: amount)
            context.insert(target)
        }
        target.vehicleID = vehicleID
        target.categoryID = categoryID
        target.date = date
        target.amount = amount
        target.odometer = NumberParser.double(odometerText)
        target.merchant = merchant.trimmingCharacters(in: .whitespaces)
        target.notes = notes
        target.receiptData = receiptData
        target.recurrenceMonths = recurrenceMonths
        target.dueDate = recurrenceMonths > 0 ? dueDate : nil
        target.reminderEnabled = recurrenceMonths > 0 && reminderEnabled
        target.remindDaysBefore = remindDaysBefore
        target.renewed = recurrenceMonths > 0 ? renewed : false
        if let renewing {
            renewing.renewed = true
        }
        try? context.save()
        ReminderEngine.rescheduleAll(context: context)
        dismiss()
    }
}
