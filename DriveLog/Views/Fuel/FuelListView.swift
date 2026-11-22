import SwiftUI
import SwiftData
import Charts

struct FuelListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \FuelEntry.date, order: .reverse) private var entries: [FuelEntry]
    @Query(sort: \Vehicle.createdAt) private var vehicles: [Vehicle]
    @AppStorage(AppSettings.currentVehicleKey) private var currentVehicleIDString: String = ""
    @AppStorage(AppSettings.currencyKey) private var currencyCode: String = AppSettings.defaultCurrency

    @State private var selectedVehicleID: UUID?
    @State private var showAdd = false
    @State private var editingEntry: FuelEntry?
    @State private var chartKind = 0

    private var vehicleID: UUID? {
        if let selectedVehicleID { return selectedVehicleID }
        if let id = UUID(uuidString: currentVehicleIDString), vehicles.contains(where: { $0.id == id }) { return id }
        return vehicles.first?.id
    }

    private var vehicle: Vehicle? {
        vehicles.first(where: { $0.id == vehicleID })
    }

    private var vehicleEntries: [FuelEntry] {
        entries.filter { $0.vehicleID == vehicleID }
    }

    var body: some View {
        let analysis = FuelEconomy.analyze(entries: vehicleEntries)
        NavigationStack {
            List {
                if vehicles.isEmpty {
                    ContentUnavailableView("先添加一辆车", systemImage: "car",
                                           description: Text("在「车辆/设置」里添加车辆后即可记录加油。"))
                } else {
                    Section {
                        summary(analysis)
                    }

                    if vehicleEntries.count >= 2 {
                        Section {
                            Picker("图表", selection: $chartKind) {
                                Text("油耗走势").tag(0)
                                Text("油价走势").tag(1)
                            }
                            .pickerStyle(.segmented)
                            if chartKind == 0 {
                                EconomyTrendChart(segments: analysis.segments, average: analysis.averageEconomy)
                            } else {
                                FuelPriceChart(entries: vehicleEntries)
                            }
                        }
                    }

                    Section {
                        if vehicleEntries.isEmpty {
                            Text("还没有加油记录，点右上角「+」添加。")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(vehicleEntries) { entry in
                            Button {
                                editingEntry = entry
                            } label: {
                                FuelRow(entry: entry, economy: analysis.economyByEntryID[entry.id])
                            }
                            .buttonStyle(.plain)
                        }
                        .onDelete { offsets in
                            let items = vehicleEntries
                            for index in offsets {
                                context.delete(items[index])
                            }
                            try? context.save()
                        }
                    } header: {
                        Text("加油记录")
                    } footer: {
                        Text("油耗按「满箱到满箱」计算：两次加满之间的所有加油量 ÷ 这段里程。中间有「上次漏记」的段不计算。")
                    }
                }
            }
            .appBackground()
            .navigationTitle("加油")
            .toolbar {
                if vehicles.count > 1 {
                    ToolbarItem(placement: .topBarLeading) {
                        Menu {
                            ForEach(vehicles) { v in
                                Button {
                                    selectedVehicleID = v.id
                                } label: {
                                    if v.id == vehicleID {
                                        Label(v.displayName, systemImage: "checkmark")
                                    } else {
                                        Text(v.displayName)
                                    }
                                }
                            }
                        } label: {
                            Label(vehicle?.displayName ?? "车辆", systemImage: "car")
                                .labelStyle(.titleAndIcon)
                        }
                    }
                }
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
                FuelEditView(entry: nil, vehicleID: vehicleID)
            }
            .sheet(item: $editingEntry) { entry in
                FuelEditView(entry: entry, vehicleID: entry.vehicleID)
            }
        }
    }

    private func summary(_ analysis: FuelAnalysis) -> some View {
        let totalCost = vehicleEntries.reduce(0) { $0 + $1.totalCost }
        let totalLiters = vehicleEntries.reduce(0) { $0 + $1.liters }
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            StatTile(title: "平均油耗", value: Fmt.economy(analysis.averageEconomy), systemImage: "gauge.with.dots.needle.33percent", tint: .orange)
            StatTile(title: "每公里油费", value: analysis.costPerKm.map { Fmt.money($0) } ?? "—", systemImage: "road.lanes", tint: .blue)
            StatTile(title: "油费合计", value: Fmt.money(totalCost), systemImage: "creditcard", tint: .pink)
            StatTile(title: "加油量合计", value: String(format: "%.1f L", totalLiters), systemImage: "drop.fill", tint: .teal)
        }
        .padding(.vertical, 4)
    }
}

struct FuelRow: View {
    let entry: FuelEntry
    let economy: Double?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: entry.isFullTank ? "fuelpump.fill" : "fuelpump")
                .font(.title3)
                .foregroundStyle(entry.isFullTank ? Color.orange : Color.secondary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(Fmt.dateShort.string(from: entry.date))
                        .font(.headline)
                    Text(entry.fuelType.displayName)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.orange.opacity(0.15)))
                    if !entry.isFullTank {
                        Text("未加满")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if entry.missedPrevious {
                        Text("上次漏记")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    Spacer()
                    Text(Fmt.money(entry.totalCost))
                        .font(.headline)
                        .monospacedDigit()
                }
                HStack {
                    Text("\(Fmt.liters(entry.liters)) × \(Fmt.unitPrice(entry.pricePerLiter))/L")
                    Spacer()
                    Text(Fmt.odometer(entry.odometer))
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                HStack {
                    if !entry.stationName.isEmpty {
                        Label(entry.stationName, systemImage: "mappin.and.ellipse")
                            .lineLimit(1)
                    }
                    Spacer()
                    if let economy {
                        Text(Fmt.economy(economy))
                            .foregroundStyle(.orange)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
        .padding(.vertical, 2)
    }
}

/// 油耗走势
struct EconomyTrendChart: View {
    let segments: [FuelSegment]
    let average: Double?

    var body: some View {
        if segments.isEmpty {
            Text("至少需要两次「加满」的记录才能计算油耗。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 80)
        } else {
            Chart {
                ForEach(segments) { segment in
                    LineMark(x: .value("日期", segment.endDate),
                             y: .value("L/100km", segment.economy))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(Color.orange)
                    PointMark(x: .value("日期", segment.endDate),
                              y: .value("L/100km", segment.economy))
                        .foregroundStyle(Color.orange)
                }
                if let average {
                    RuleMark(y: .value("平均", average))
                        .foregroundStyle(Color.secondary)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .annotation(position: .top, alignment: .leading) {
                            Text("平均 \(String(format: "%.1f", average))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                }
            }
            .chartYScale(domain: .automatic(includesZero: false))
            .chartYAxisLabel("L/100km")
            .frame(height: 200)
        }
    }
}

/// 油价走势
struct FuelPriceChart: View {
    let entries: [FuelEntry]

    var body: some View {
        let sorted = entries.filter { $0.pricePerLiter > 0 }.sorted { $0.date < $1.date }
        if sorted.count < 2 {
            Text("数据不足")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 80)
        } else {
            Chart(sorted) { entry in
                LineMark(x: .value("日期", entry.date),
                         y: .value("单价", entry.pricePerLiter))
                    .foregroundStyle(by: .value("燃油", entry.fuelType.displayName))
                    .interpolationMethod(.monotone)
                PointMark(x: .value("日期", entry.date),
                          y: .value("单价", entry.pricePerLiter))
                    .foregroundStyle(by: .value("燃油", entry.fuelType.displayName))
            }
            .chartYScale(domain: .automatic(includesZero: false))
            .chartYAxisLabel("\(Fmt.currencySymbol)/L")
            .frame(height: 200)
        }
    }
}
