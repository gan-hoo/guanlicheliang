import SwiftUI
import SwiftData

/// 「车辆 / 设置」Tab
struct GarageView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Vehicle.createdAt) private var vehicles: [Vehicle]
    @Query private var trips: [Trip]
    @Query private var fuelEntries: [FuelEntry]
    @Query private var expenses: [Expense]
    @AppStorage(AppSettings.currentVehicleKey) private var currentVehicleIDString: String = ""
    @AppStorage(AppSettings.currencyKey) private var currencyCode: String = AppSettings.defaultCurrency
    @ObservedObject private var recorder = TripRecorder.shared

    @State private var showAddVehicle = false
    @State private var vehiclePendingDelete: Vehicle?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(vehicles) { vehicle in
                        NavigationLink {
                            VehicleDetailView(vehicle: vehicle)
                        } label: {
                            VehicleRow(vehicle: vehicle,
                                       isCurrent: vehicle.id.uuidString == currentVehicleIDString,
                                       odometer: OdometerService.estimate(vehicle: vehicle, trips: trips, fuel: fuelEntries, expenses: expenses))
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                vehiclePendingDelete = vehicle
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .leading) {
                            Button {
                                currentVehicleIDString = vehicle.id.uuidString
                            } label: {
                                Label("设为当前", systemImage: "checkmark.circle")
                            }
                            .tint(.green)
                        }
                    }
                    Button {
                        showAddVehicle = true
                    } label: {
                        Label("添加车辆", systemImage: "plus.circle.fill")
                    }
                } header: {
                    Text("车辆")
                } footer: {
                    Text("左滑删除，右滑设为当前车辆。新行程会自动归到当前车辆。")
                }

                Section("自动记录") {
                    NavigationLink {
                        ShortcutGuideView()
                    } label: {
                        Label("快捷指令自动化设置步骤", systemImage: "wand.and.stars")
                    }
                    NavigationLink {
                        PermissionStatusView()
                    } label: {
                        HStack {
                            Label("定位与通知权限", systemImage: "location.circle")
                            Spacer()
                            Text(recorder.hasFullBackgroundPermission ? "正常" : "需要处理")
                                .foregroundStyle(recorder.hasFullBackgroundPermission ? Color.green : Color.orange)
                        }
                    }
                }

                Section("数据") {
                    NavigationLink {
                        ExpenseCategoryManagerView()
                    } label: {
                        Label("费用分类", systemImage: "square.grid.2x2")
                    }
                    NavigationLink {
                        MaintenanceListView()
                    } label: {
                        Label("保养提醒", systemImage: "bell.badge")
                    }
                    NavigationLink {
                        ExportCenterView()
                    } label: {
                        Label("导出 CSV", systemImage: "tablecells")
                    }
                    NavigationLink {
                        BackupView()
                    } label: {
                        Label("备份与恢复", systemImage: "externaldrive.badge.timemachine")
                    }
                }

                Section("通用") {
                    Picker(selection: $currencyCode) {
                        ForEach(AppSettings.currencies) { option in
                            Text("\(option.name) \(option.code)").tag(option.code)
                        }
                    } label: {
                        Label("货币", systemImage: "dollarsign.circle")
                    }
                }

                Section("关于") {
                    InfoRow(title: "版本", value: appVersion)
                    Text("数据只保存在本机。侧载的 App 一旦删除，数据会一起丢失，请定期在「备份与恢复」里导出备份，并存到 iCloud 云盘等其他位置。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .appBackground()
            .navigationTitle("车辆与设置")
            .pageHeader("车辆与设置")
            .sheet(isPresented: $showAddVehicle) {
                VehicleEditView(vehicle: nil)
            }
            .confirmationDialog(
                "删除「\(vehiclePendingDelete?.displayName ?? "")」？",
                isPresented: Binding(
                    get: { vehiclePendingDelete != nil },
                    set: { if !$0 { vehiclePendingDelete = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("删除车辆及其所有记录", role: .destructive) {
                    if let vehicle = vehiclePendingDelete {
                        VehicleService.delete(vehicle, context: context)
                        currentVehicleIDString = AppSettings.currentVehicleID?.uuidString ?? ""
                    }
                    vehiclePendingDelete = nil
                }
                Button("取消", role: .cancel) {
                    vehiclePendingDelete = nil
                }
            } message: {
                Text("这辆车的所有行程、加油、费用和保养提醒都会被删除，无法撤销。")
            }
        }
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}

struct VehicleRow: View {
    let vehicle: Vehicle
    let isCurrent: Bool
    let odometer: Double

    var body: some View {
        HStack(spacing: 12) {
            VehicleAvatar(photoData: vehicle.photoData, size: 54)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(vehicle.displayName)
                        .font(.headline)
                    if isCurrent {
                        Label("当前", systemImage: "checkmark.seal.fill")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Theme.altitude)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Theme.altitude.opacity(0.14)))
                    }
                }
                let subtitle = [vehicle.subtitle, vehicle.plate].filter { !$0.isEmpty }.joined(separator: " · ")
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Text("估算里程 \(Fmt.odometer(odometer))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
