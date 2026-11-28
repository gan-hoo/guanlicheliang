import SwiftUI
import SwiftData

struct TripDetailView: View {
    @Bindable var trip: Trip
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Vehicle.createdAt) private var vehicles: [Vehicle]

    @State private var isLoading = true
    @State private var segments: [SpeedSegment] = []
    @State private var speedSamples: [ChartSample] = []
    @State private var altitudeSamples: [ChartSample] = []
    @State private var chartKind = 0
    @State private var showFullMap = false
    @State private var showDeleteConfirm = false
    @State private var gpxURL: URL?
    @State private var csvURL: URL?

    var body: some View {
        List {
            Group {
                Section {
                    mapArea
                        .frame(height: 320)
                        .listRowInsets(EdgeInsets())
                }

                Section("概要") {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        StatTile(title: "距离", value: Fmt.distance(trip.distance), systemImage: "road.lanes", tint: Theme.distance)
                        StatTile(title: "总时长", value: Fmt.duration(trip.duration), systemImage: "clock.fill", tint: Theme.duration)
                        StatTile(title: "行驶时长", value: Fmt.duration(trip.movingDuration), systemImage: "steeringwheel", tint: Theme.duration)
                        StatTile(title: "行驶均速", value: Fmt.speed(trip.averageMovingSpeed), systemImage: "speedometer", tint: Theme.speed)
                        StatTile(title: "最高速度", value: Fmt.speed(trip.maxSpeed), systemImage: "bolt.fill", tint: Theme.maxSpeed)
                        StatTile(title: "累计爬升", value: "\(Int(trip.elevationGain.rounded())) m", systemImage: "arrow.up.right", tint: Theme.altitude)
                        StatTile(title: "最低海拔", value: Fmt.altitude(trip.minAltitude), systemImage: "arrow.down.to.line", tint: Theme.altitude)
                        StatTile(title: "最高海拔", value: Fmt.altitude(trip.maxAltitude), systemImage: "mountain.2.fill", tint: Theme.altitude)
                    }
                    .padding(.vertical, 4)
                    InfoRow(title: "开始", value: Fmt.dateTimeFull.string(from: trip.startDate))
                    InfoRow(title: "结束", value: Fmt.dateTimeFull.string(from: trip.endDate))
                    if let start = trip.startAddress, !start.isEmpty {
                        InfoRow(title: "起点", value: start)
                    }
                    if let end = trip.endAddress, !end.isEmpty {
                        InfoRow(title: "终点", value: end)
                    }
                    InfoRow(title: "GPS 点数", value: "\(trip.pointCount)")
                }

                Section("曲线") {
                    Picker("曲线", selection: $chartKind) {
                        Text("速度").tag(0)
                        Text("海拔").tag(1)
                    }
                    .pickerStyle(.segmented)
                    if isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity, minHeight: 200)
                    } else if chartKind == 0 {
                        TrackChartView(samples: speedSamples, unit: "km/h", color: Theme.speed,
                                       gradientColors: SpeedBand.allCases.map(\.color))
                    } else {
                        TrackChartView(samples: altitudeSamples, unit: "m", color: Theme.altitude, showsArea: false, includesZero: false)
                    }
                }

                Section("车辆") {
                    Picker("归属车辆", selection: $trip.vehicleID) {
                        Text("未指定").tag(UUID?.none)
                        ForEach(vehicles) { vehicle in
                            Text(vehicle.displayName).tag(UUID?.some(vehicle.id))
                        }
                    }
                }

                Section("备注") {
                    TextField("添加备注", text: $trip.notes, axis: .vertical)
                        .lineLimit(1...5)
                }

                Section {
                    if let gpxURL {
                        ShareLink(item: gpxURL) {
                            Label("分享 GPX", systemImage: "square.and.arrow.up")
                        }
                    }
                    if let csvURL {
                        ShareLink(item: csvURL) {
                            Label("分享原始 CSV", systemImage: "tablecells")
                        }
                    }
                } header: {
                    Text("导出")
                } footer: {
                    Text("GPX 和 CSV 已自动保存在「文件」App → 我的 iPhone → 行车记录 → 行程轨迹。")
                }

                Section {
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Label("删除这段行程", systemImage: "trash")
                    }
                }
            }
            .listRowBackground(Theme.rowFill)
        }
        .appBackground()
        .navigationTitle(Fmt.dateTimeShort.string(from: trip.startDate))
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: trip.vehicleID) { _, _ in
            try? context.save()
        }
        .confirmationDialog("删除这段行程？", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                let target = trip
                dismiss()
                // 先返回列表再删除，避免详情页访问已删除的对象
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    TripService.delete(target, context: context)
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("轨迹和导出的 GPX / CSV 文件也会一起删除。")
        }
        .fullScreenCover(isPresented: $showFullMap) {
            FullScreenTripMap(segments: segments, start: trip.startCoordinate, end: trip.endCoordinate)
        }
        .task {
            await load()
        }
    }

    @ViewBuilder
    private var mapArea: some View {
        if isLoading {
            ZStack {
                Color(uiColor: .tertiarySystemFill)
                ProgressView()
            }
        } else if segments.isEmpty {
            ZStack {
                Color(uiColor: .tertiarySystemFill)
                Text("没有轨迹数据")
                    .foregroundStyle(.secondary)
            }
        } else {
            TripMapView(segments: segments, start: trip.startCoordinate, end: trip.endCoordinate)
                .overlay(alignment: .topTrailing) {
                    // 玻璃不接管触摸（interactive 的玻璃会吃掉点击），整个圆都能点
                    Button {
                        showFullMap = true
                    } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.body.weight(.semibold))
                            .frame(width: 40, height: 40)
                            .glassCircle(interactive: false)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .padding(10)
                }
                .overlay(alignment: .bottom) {
                    SpeedLegendView()
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .glassCapsule()
                        .padding(10)
                }
        }
    }

    private func load() async {
        let id = trip.id
        let startDate = trip.startDate
        let points = await Task.detached(priority: .userInitiated) {
            TrackStore.readPoints(for: id)
        }.value
        segments = TrackAnalysis.segments(for: points)
        speedSamples = TrackAnalysis.speedSamples(for: points)
        altitudeSamples = TrackAnalysis.altitudeSamples(for: points)
        isLoading = false

        if !points.isEmpty {
            TripExporter.ensureExports(id: id, startDate: startDate, points: points)
        }
        let fm = FileManager.default
        let gpx = TripExporter.gpxURL(id: id, startDate: startDate)
        let csv = TripExporter.csvURL(id: id, startDate: startDate)
        gpxURL = fm.fileExists(atPath: gpx.path) ? gpx : nil
        csvURL = fm.fileExists(atPath: csv.path) ? csv : nil
    }
}
