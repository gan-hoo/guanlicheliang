import Foundation
import CoreLocation
import SwiftData
import UIKit

/// 正在进行的行程（写在 Application Support/active_trip.json，用于被杀后恢复）
struct ActiveTripState: Codable {
    var id: UUID
    var startDate: Date
    var vehicleID: UUID?
    var lastUpdate: Date
}

enum TripTrigger: String {
    case manual = "手动"
    case shortcut = "快捷指令"
}

/// 行程记录核心。单例，不依赖任何视图：
/// App Intent 在后台启动 App 时、系统因 significant location change 重新唤醒 App 时都能直接用。
@MainActor
final class TripRecorder: NSObject, ObservableObject {
    static let shared = TripRecorder()

    /// 未收尾的行程：最后一个点在这个时间内就接着记，否则直接收尾
    static let resumeWindow: TimeInterval = 30 * 60
    /// 短于 100 m 的行程自动丢弃
    static let minimumTripDistance: Double = 100
    /// 超过这个秒数没有新定位，实时速度显示为 0
    static let speedStaleInterval: TimeInterval = 6

    enum StartOutcome {
        case started
        case alreadyRecording
        case failed(String)
    }

    enum StopOutcome {
        case saved(String)
        case discarded(String)
        case notRecording
    }

    // MARK: 实时状态
    @Published private(set) var isRecording = false
    @Published private(set) var activeTripID: UUID?
    @Published private(set) var activeVehicleID: UUID?
    @Published private(set) var startDate: Date?
    @Published private(set) var distance: Double = 0
    @Published private(set) var movingDuration: Double = 0
    @Published private(set) var maxSpeed: Double = 0
    @Published private(set) var currentSpeed: Double = 0
    @Published private(set) var currentAltitude: Double?
    @Published private(set) var horizontalAccuracy: Double?
    @Published private(set) var lastFixDate: Date?
    @Published private(set) var pointCount: Int = 0
    @Published private(set) var lastSavedTripID: UUID?

    // MARK: 权限状态
    @Published private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published private(set) var accuracyAuthorization: CLAccuracyAuthorization = .fullAccuracy
    @Published private(set) var locationServicesEnabled = true

    private let manager = CLLocationManager()
    private var state: ActiveTripState?
    private var writer: TrackWriter?
    private var accumulator = TripAccumulator()
    private var didBootstrap = false
    private var lastStateSave = Date.distantPast
    private var observers: [NSObjectProtocol] = []

    private override init() {
        super.init()
        manager.delegate = self
        manager.activityType = .automotiveNavigation
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.distanceFilter = 5
        manager.pausesLocationUpdatesAutomatically = false
        authorizationStatus = manager.authorizationStatus
        accuracyAuthorization = manager.accuracyAuthorization
        installObservers()
        refreshLocationServicesEnabled()
    }

    // MARK: - 启动恢复

    /// App 每次启动（前台、后台被 Intent 拉起、被 significant location change 唤醒）都会调用。
    /// 发现没收尾的行程：最后一个点在 30 分钟内就接着记，否则直接收尾保存。
    func bootstrap() {
        guard !didBootstrap else { return }
        didBootstrap = true

        guard let saved = loadState() else {
            // 没有进行中的行程，确保不会残留 significant change 监听
            manager.stopMonitoringSignificantLocationChanges()
            return
        }

        let points = TrackStore.readPoints(for: saved.id)
        let lastDate = points.last?.timestamp ?? saved.startDate
        if Date().timeIntervalSince(lastDate) <= Self.resumeWindow {
            resume(saved, points: points)
        } else {
            var acc = TripAccumulator()
            for point in points {
                acc.add(point)
            }
            finalize(state: saved,
                     accumulator: acc,
                     points: points,
                     endDate: max(lastDate, saved.startDate),
                     note: "上次记录被中断，已自动收尾")
        }
    }

    private func resume(_ saved: ActiveTripState, points: [TrackPoint]) {
        var acc = TripAccumulator()
        for point in points {
            acc.add(point)
        }
        accumulator = acc
        state = saved
        do {
            writer = try TrackWriter(fileURL: TrackStore.url(for: saved.id))
        } catch {
            writer = nil
            print("恢复轨迹文件失败：\(error)")
        }
        isRecording = true
        activeTripID = saved.id
        activeVehicleID = saved.vehicleID
        startDate = saved.startDate
        lastFixDate = points.last?.timestamp
        currentSpeed = 0
        publishStats()
        startLocationServices()
        saveState()

        NotificationManager.shared.post(
            title: "已恢复行程记录",
            body: "发现未完成的行程（\(Fmt.time.string(from: saved.startDate)) 开始，已记录 \(Fmt.distance(acc.distance))），继续记录中。"
        )
    }

    // MARK: - 开始 / 停止

    @discardableResult
    func startRecording(trigger: TripTrigger) -> StartOutcome {
        bootstrap()
        if isRecording { return .alreadyRecording }

        refreshAuthorization()
        switch authorizationStatus {
        case .denied, .restricted:
            NotificationManager.shared.post(
                title: "无法记录行程",
                body: "定位权限未开启。请到 设置 → 行车记录 → 位置，选择「始终」并打开「精确位置」。"
            )
            return .failed("定位权限未开启")
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        default:
            break
        }

        let vehicleID = resolvedCurrentVehicleID()
        let newState = ActiveTripState(id: UUID(), startDate: Date(), vehicleID: vehicleID, lastUpdate: Date())
        do {
            try TrackStore.createEmpty(for: newState.id)
            writer = try TrackWriter(fileURL: TrackStore.url(for: newState.id))
        } catch {
            NotificationManager.shared.post(title: "无法记录行程", body: "创建轨迹文件失败：\(error.localizedDescription)")
            return .failed(error.localizedDescription)
        }

        state = newState
        accumulator = TripAccumulator()
        isRecording = true
        activeTripID = newState.id
        activeVehicleID = vehicleID
        startDate = newState.startDate
        currentSpeed = 0
        currentAltitude = nil
        lastFixDate = nil
        publishStats()
        saveState()
        startLocationServices()

        var body = "车辆：\(vehicleName(for: vehicleID)) · 触发方式：\(trigger.rawValue)"
        if authorizationStatus == .authorizedWhenInUse {
            body += "\n⚠️ 定位权限不是「始终」，锁屏或后台时可能无法记录"
        }
        if accuracyAuthorization == .reducedAccuracy {
            body += "\n⚠️「精确位置」已关闭，轨迹会不准"
        }
        NotificationManager.shared.post(title: "开始记录行程", body: body)
        return .started
    }

    @discardableResult
    func stopRecording(trigger: TripTrigger) -> StopOutcome {
        bootstrap()
        guard isRecording, let current = state else { return .notRecording }

        stopLocationServices()
        writer?.close()
        writer = nil
        let points = TrackStore.readPoints(for: current.id)
        let outcome = finalize(state: current, accumulator: accumulator, points: points, endDate: Date(), note: nil)
        resetLiveState()
        return outcome
    }

    /// 记录中修改这段行程归属的车辆
    func setActiveVehicle(_ id: UUID?) {
        guard isRecording, var current = state else { return }
        current.vehicleID = id
        state = current
        activeVehicleID = id
        saveState()
    }

    /// 实时速度：太久没有新定位（停车时 distanceFilter 不会回调）就显示 0
    func displaySpeed(at date: Date) -> Double {
        guard let lastFixDate, date.timeIntervalSince(lastFixDate) <= Self.speedStaleInterval else { return 0 }
        return currentSpeed
    }

    var averageMovingSpeed: Double {
        movingDuration > 0 ? distance / movingDuration : 0
    }

    // MARK: - 保存

    @discardableResult
    private func finalize(state current: ActiveTripState,
                          accumulator acc: TripAccumulator,
                          points: [TrackPoint],
                          endDate: Date,
                          note: String?) -> StopOutcome {
        clearState()
        state = nil

        if acc.distance < Self.minimumTripDistance {
            TrackStore.delete(current.id)
            let message = "距离仅 \(Int(acc.distance.rounded())) m（少于 100 m），已自动丢弃。"
            NotificationManager.shared.post(title: "行程过短，未保存", body: message)
            return .discarded(message)
        }

        let trip = Trip(id: current.id, vehicleID: current.vehicleID, startDate: current.startDate, endDate: endDate)
        trip.apply(acc)
        let context = DataStore.shared.context
        context.insert(trip)
        DataStore.shared.save()

        TripExporter.export(trip: trip, points: points)

        let summary = "\(Fmt.distance(trip.distance)) · \(Fmt.duration(trip.duration)) · 最高 \(Fmt.speed(trip.maxSpeed))"
        var body = "车辆：\(vehicleName(for: trip.vehicleID)) · \(Fmt.time.string(from: trip.startDate))–\(Fmt.time.string(from: trip.endDate))"
        if let note { body += "\n\(note)" }
        NotificationManager.shared.post(title: "行程已保存：\(summary)", body: body)
        lastSavedTripID = trip.id

        ReminderEngine.tripSaved(context: context)

        Task { @MainActor in
            await TripService.geocode(trip)
            DataStore.shared.save()
        }
        return .saved(summary)
    }

    private func resetLiveState() {
        isRecording = false
        activeTripID = nil
        activeVehicleID = nil
        startDate = nil
        distance = 0
        movingDuration = 0
        maxSpeed = 0
        currentSpeed = 0
        currentAltitude = nil
        horizontalAccuracy = nil
        lastFixDate = nil
        pointCount = 0
        accumulator = TripAccumulator()
    }

    private func publishStats() {
        distance = accumulator.distance
        movingDuration = accumulator.movingDuration
        maxSpeed = accumulator.maxSpeed
        pointCount = accumulator.pointCount
        if let altitude = accumulator.currentAltitude {
            currentAltitude = altitude
        }
    }

    // MARK: - 定位

    private func startLocationServices() {
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        manager.startUpdatingLocation()
        // 被系统杀掉后，significant location change 会把 App 重新唤醒，接着记
        if CLLocationManager.significantLocationChangeMonitoringAvailable() {
            manager.startMonitoringSignificantLocationChanges()
        }
    }

    private func stopLocationServices() {
        manager.stopUpdatingLocation()
        manager.stopMonitoringSignificantLocationChanges()
        manager.allowsBackgroundLocationUpdates = false
    }

    private func handle(_ locations: [CLLocation]) {
        guard isRecording, let current = state else { return }
        var accepted = false
        let now = Date()

        for location in locations {
            let accuracy = location.horizontalAccuracy
            horizontalAccuracy = accuracy >= 0 ? accuracy : nil
            // 精度过差
            guard accuracy >= 0, accuracy <= TripAccumulator.maxHorizontalAccuracy else { continue }
            // 过期的缓存点
            guard now.timeIntervalSince(location.timestamp) <= 20,
                  location.timestamp >= current.startDate.addingTimeInterval(-2) else { continue }

            let point = TrackPoint(location: location)
            if accumulator.add(point) {
                writer?.append(point)
                accepted = true
            }
            currentSpeed = max(0, location.speed)
            lastFixDate = location.timestamp
        }

        if accepted {
            publishStats()
        }
        if now.timeIntervalSince(lastStateSave) >= 30 {
            saveState()
        }
    }

    // MARK: - 权限

    func requestWhenInUseAuthorization() {
        manager.requestWhenInUseAuthorization()
    }

    func requestAlwaysAuthorization() {
        manager.requestAlwaysAuthorization()
    }

    func refreshAuthorization() {
        authorizationStatus = manager.authorizationStatus
        accuracyAuthorization = manager.accuracyAuthorization
        refreshLocationServicesEnabled()
    }

    private func refreshLocationServicesEnabled() {
        Task.detached(priority: .utility) {
            let enabled = CLLocationManager.locationServicesEnabled()
            await MainActor.run {
                TripRecorder.shared.locationServicesEnabled = enabled
            }
        }
    }

    var hasFullBackgroundPermission: Bool {
        authorizationStatus == .authorizedAlways && accuracyAuthorization == .fullAccuracy && locationServicesEnabled
    }

    // MARK: - 状态文件

    private func saveState() {
        guard var current = state else { return }
        current.lastUpdate = Date()
        state = current
        lastStateSave = Date()
        do {
            let data = try JSONEncoder().encode(current)
            try data.write(to: AppPaths.activeTripStateURL, options: .atomic)
        } catch {
            print("保存行程状态失败：\(error)")
        }
    }

    private func loadState() -> ActiveTripState? {
        guard let data = try? Data(contentsOf: AppPaths.activeTripStateURL) else { return nil }
        return try? JSONDecoder().decode(ActiveTripState.self, from: data)
    }

    private func clearState() {
        try? FileManager.default.removeItem(at: AppPaths.activeTripStateURL)
    }

    /// 进入后台 / 即将退出时，立刻把缓冲写盘
    private func persistNow() {
        writer?.flush()
        if isRecording {
            saveState()
        }
    }

    private func installObservers() {
        let center = NotificationCenter.default
        let names: [Notification.Name] = [
            UIApplication.willResignActiveNotification,
            UIApplication.didEnterBackgroundNotification,
            UIApplication.willTerminateNotification
        ]
        for name in names {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated {
                    TripRecorder.shared.persistNow()
                }
            }
            observers.append(token)
        }
    }

    // MARK: - 车辆

    private func resolvedCurrentVehicleID() -> UUID? {
        let vehicles = (try? DataStore.shared.context.fetch(FetchDescriptor<Vehicle>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
        if let current = AppSettings.currentVehicleID, vehicles.contains(where: { $0.id == current }) {
            return current
        }
        let fallback = vehicles.first?.id
        AppSettings.currentVehicleID = fallback
        return fallback
    }

    private func vehicleName(for id: UUID?) -> String {
        guard let id else { return "未指定" }
        let vehicles = (try? DataStore.shared.context.fetch(FetchDescriptor<Vehicle>())) ?? []
        return vehicles.first(where: { $0.id == id })?.displayName ?? "未指定"
    }
}

// MARK: - CLLocationManagerDelegate

extension TripRecorder: CLLocationManagerDelegate {
    // CLLocationManager 在主线程创建，回调也在主线程
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        MainActor.assumeIsolated {
            TripRecorder.shared.handle(locations)
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        MainActor.assumeIsolated {
            TripRecorder.shared.refreshAuthorization()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // kCLErrorLocationUnknown 是暂时性错误，忽略；权限被拒会走 didChangeAuthorization
        print("定位错误：\(error.localizedDescription)")
    }
}
