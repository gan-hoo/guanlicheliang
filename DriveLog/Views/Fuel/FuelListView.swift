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
                Group {
                    if vehicles.isEmpty {
                        ContentUnavailableView("先添加一辆车", systemImage: "car",
                                               description: Text("在「车辆/设置」里添加车辆后即可记录加油。"))
                    } else {
                        Section {
                        } header: {
                            summary(analysis)
                                .glassListHeader(topSpacing: Theme.firstCardTopSpacing)
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
                .listRowBackground(Theme.rowFill)
            }
            .tabSwitchEffect(.fuel)
            .appBackground()
            .navigationTitle("加油")
            .pageHeader("加油") {
                if vehicles.count > 1 {
                    HeaderButtonGroup {
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
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.tint)
                                .lineLimit(1)
                                .padding(.horizontal, 12)
                                .frame(height: 44)
                        }
                    }
                }
                HeaderButtonGroup {
                    Button {
                        showAdd = true
                    } label: {
                        HeaderIcon(systemName: "plus")
                    }
                    .buttonStyle(.plain)
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
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("平均油耗")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                    if let economy = analysis.averageEconomy {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(String(format: "%.1f", economy))
                                .font(.numeric(44, weight: .bold))
                                .foregroundStyle(Theme.fuelGradient)
                                .contentTransition(.numericText())
                            Text("L/100km")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("暂无数据")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                        Text("记录两次「加满」后自动计算")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer()
                MetricIcon(systemName: "fuelpump.fill", tint: Theme.fuel, size: 44)
            }
            HStack(spacing: 10) {
                StatTile(title: "每公里", value: analysis.costPerKm.map { Fmt.money($0) } ?? "—", systemImage: "road.lanes", tint: Theme.distance)
                StatTile(title: "油费", value: Fmt.money(totalCost), systemImage: "creditcard.fill", tint: Theme.money)
                StatTile(title: "加油量", value: String(format: "%.0f L", totalLiters), systemImage: "drop.fill", tint: Theme.fuel)
            }
        }
        .animation(.snappy, value: analysis.averageEconomy ?? 0)
    }
}

struct FuelRow: View {
    let entry: FuelEntry
    let economy: Double?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: entry.isFullTank ? "fuelpump.fill" : "fuelpump")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(entry.isFullTank
                              ? AnyShapeStyle(LinearGradient(colors: [Theme.fuel, Theme.fuel.opacity(0.7)], startPoint: .top, endPoint: .bottom))
                              : AnyShapeStyle(Color.gray.opacity(0.5)))
                )
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
                        .font(.numeric(17, weight: .bold))
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
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.fuel)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Theme.fuel.opacity(0.14)))
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

    private var lowerBound: Double {
        max(0, (segments.map(\.economy).min() ?? 0) - 1)
    }

    var body: some View {
        if segments.isEmpty {
            Text("至少需要两次「加满」的记录才能计算油耗。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 80)
        } else {
            Chart {
                ForEach(segments) { segment in
                    AreaMark(x: .value("日期", segment.endDate),
                             yStart: .value("底", lowerBound),
                             yEnd: .value("L/100km", segment.economy))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(LinearGradient(colors: [Theme.fuel.opacity(0.28), Theme.fuel.opacity(0.02)],
                                                        startPoint: .top, endPoint: .bottom))
                    LineMark(x: .value("日期", segment.endDate),
                             y: .value("L/100km", segment.economy))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(Theme.fuel)
                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    PointMark(x: .value("日期", segment.endDate),
                              y: .value("L/100km", segment.economy))
                        .foregroundStyle(Theme.fuel)
                        .symbolSize(36)
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
            .chartYScale(domain: lowerBound...((segments.map(\.economy).max() ?? 10) + 1))
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
