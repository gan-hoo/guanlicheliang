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
    /// 自动检测开始的行程：停车一段时间后自动结束（nil 视为否，兼容旧状态文件）
    var autoStop: Bool?
    /// 最后一次处于行驶速度的时间（自动结束用）
    var lastDrivingDate: Date?
}

enum TripTrigger: String {
    case manual = "手动"
    case shortcut = "快捷指令"
    case auto = "自动检测"
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

    // 自动检测驾驶
    /// 车速超过约 22 km/h 的定位点达到 3 个，判定为开车
    static let autoStartSpeed: Double = 6
    static let autoStartFixes = 3
    /// 每次唤醒后最多用 GPS 探测 90 秒
    static let probeDuration: TimeInterval = 90
    /// 车速超过约 11 km/h 视为仍在行驶
    static let drivingSpeed: Double = 3
    /// 自动开始的行程：停车超过 5 分钟自动结束
    static let autoStopAfter: TimeInterval = 5 * 60
    /// 停车点周围的地理围栏半径，离开就唤醒 App 探测
    static let geofenceRadius: CLLocationDistance = 150
    static let geofenceID = "drivelog.autodetect.lastStop"

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

    // 自动检测驾驶的探测状态
    private var isProbing = false
    private var probeStart = Date.distantPast
    private var probeFastFixes = 0
    private var probeBuffer: [TrackPoint] = []
    private var probeTimer: Timer?
    private var autoStopTimer: Timer?

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
            // 没有进行中的行程：按设置开启 / 关闭自动检测驾驶
            updateAutoDetection()
            return
        }

        let points = TrackStore.readPoints(for: saved.id)
        let lastDate = points.last?.timestamp ?? saved.startDate
        if saved.autoStop == true,
           Date().timeIntervalSince(saved.lastDrivingDate ?? lastDate) >= Self.autoStopAfter {
            // 自动开始的行程在 App 被杀期间已经停车超过 5 分钟：直接收尾
            finalizeTrimmed(state: saved, points: points,
                            until: saved.lastDrivingDate ?? lastDate,
                            note: "停车超过 5 分钟，自动结束")
            updateAutoDetection()
        } else if Date().timeIntervalSince(lastDate) <= Self.resumeWindow {
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
            updateAutoDetection()
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
        if saved.autoStop == true {
            startAutoStopTimer()
        }

        NotificationManager.shared.post(
            title: "已恢复行程记录",
            body: "发现未完成的行程（\(Fmt.time.string(from: saved.startDate)) 开始，已记录 \(Fmt.distance(acc.distance))），继续记录中。"
        )
    }

    // MARK: - 开始 / 停止

    @discardableResult
    func startRecording(trigger: TripTrigger, startDate tripStart: Date? = nil, seed: [TrackPoint] = []) -> StartOutcome {
        bootstrap()
        if isRecording {
            // 已经在记录（例如自动检测开始的）：不重复开始。
            // CarPlay 连上后由快捷指令负责结束，不再按停车时间自动结束。
            if trigger == .shortcut, state?.autoStop == true {
                state?.autoStop = false
                saveState()
                autoStopTimer?.invalidate()
                autoStopTimer = nil
            }
            return .alreadyRecording
        }

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
        let isAuto = trigger == .auto
        let newState = ActiveTripState(id: UUID(),
                                       startDate: tripStart ?? Date(),
                                       vehicleID: vehicleID,
                                       lastUpdate: Date(),
                                       autoStop: isAuto ? true : nil,
                                       lastDrivingDate: isAuto ? Date() : nil)
        do {
            try TrackStore.createEmpty(for: newState.id)
            writer = try TrackWriter(fileURL: TrackStore.url(for: newState.id))
        } catch {
            NotificationManager.shared.post(title: "无法记录行程", body: "创建轨迹文件失败：\(error.localizedDescription)")
            return .failed(error.localizedDescription)
        }

        // 结束自动检测的探测和停车点围栏（记录中不需要）
        isProbing = false
        probeTimer?.invalidate()
        probeTimer = nil
        probeBuffer = []
        removeGeofences()

        state = newState
        accumulator = TripAccumulator()
        isRecording = true
        activeTripID = newState.id
        activeVehicleID = vehicleID
        startDate = newState.startDate
        currentSpeed = 0
        currentAltitude = nil
        lastFixDate = nil
        // 自动检测：把探测期间的定位点补进行程，开头那一段不会丢
        for point in seed {
            if accumulator.add(point) {
                writer?.append(point)
            }
        }
        publishStats()
        saveState()
        startLocationServices()
        if isAuto {
            startAutoStopTimer()
        }

        var body = "车辆：\(vehicleName(for: vehicleID)) · 触发方式：\(trigger.rawValue)"
        if isAuto {
            body += "\n没连 CarPlay 时，停车超过 5 分钟会自动结束保存"
        }
        if authorizationStatus == .authorizedWhenInUse {
            body += "\n⚠️ 定位权限不是「始终」，锁屏或后台时可能无法记录"
        }
        if accuracyAuthorization == .reducedAccuracy {
            body += "\n⚠️「精确位置」已关闭，轨迹会不准"
        }
        NotificationManager.shared.post(title: isAuto ? "自动开始记录行程" : "开始记录行程", body: body)
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
        updateAutoDetection()
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
        autoStopTimer?.invalidate()
        autoStopTimer = nil
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
        if !AppSettings.autoDetectDriving {
            manager.stopMonitoringSignificantLocationChanges()
        }
        manager.allowsBackgroundLocationUpdates = false
    }

    private func handle(_ locations: [CLLocation]) {
        guard isRecording, let current = state else {
            handleWhileIdle(locations)
            return
        }
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
        if current.autoStop == true {
            let drivingTimes = locations
                .filter { $0.speed >= Self.drivingSpeed && $0.horizontalAccuracy >= 0 && $0.horizontalAccuracy <= TripAccumulator.maxHorizontalAccuracy }
                .map(\.timestamp)
            if let latest = drivingTimes.max() {
                state?.lastDrivingDate = latest
            }
        }
        if now.timeIntervalSince(lastStateSave) >= 30 {
            saveState()
        }
        autoStopIfIdle()
    }

    // MARK: - 自动检测驾驶

    /// 没在记录时：开着自动检测就保持低功耗监听（significant change + 停车点地理围栏），否则全部关闭
    func updateAutoDetection() {
        guard !isRecording else { return }
        let enabled = AppSettings.autoDetectDriving && manager.authorizationStatus == .authorizedAlways
        if enabled {
            if CLLocationManager.significantLocationChangeMonitoringAvailable() {
                manager.startMonitoringSignificantLocationChanges()
            }
            if !isProbing {
                armGeofence(at: manager.location)
            }
        } else {
            if isProbing {
                endProbe()
            }
            manager.stopMonitoringSignificantLocationChanges()
            removeGeofences()
        }
    }

    private func armGeofence(at location: CLLocation?) {
        removeGeofences()
        guard let location, CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else { return }
        let region = CLCircularRegion(center: location.coordinate, radius: Self.geofenceRadius, identifier: Self.geofenceID)
        region.notifyOnEntry = false
        region.notifyOnExit = true
        manager.startMonitoring(for: region)
    }

    private func removeGeofences() {
        for region in manager.monitoredRegions where region.identifier == Self.geofenceID {
            manager.stopMonitoring(for: region)
        }
    }

    /// 被唤醒（离开停车点 / 位置明显变化）后，用 GPS 看一下是不是在开车
    private func beginProbe() {
        guard !isRecording, !isProbing,
              AppSettings.autoDetectDriving,
              manager.authorizationStatus == .authorizedAlways else { return }
        isProbing = true
        probeStart = Date()
        probeFastFixes = 0
        probeBuffer = []
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = false
        manager.startUpdatingLocation()
        probeTimer?.invalidate()
        probeTimer = Timer.scheduledTimer(withTimeInterval: Self.probeDuration + 5, repeats: false) { _ in
            MainActor.assumeIsolated {
                TripRecorder.shared.endProbeIfIdle()
            }
        }
    }

    private func handleWhileIdle(_ locations: [CLLocation]) {
        guard AppSettings.autoDetectDriving, manager.authorizationStatus == .authorizedAlways else { return }
        guard isProbing else {
            // significant change 唤醒：开始一次探测
            beginProbe()
            return
        }
        let now = Date()
        for location in locations {
            guard location.horizontalAccuracy >= 0,
                  location.horizontalAccuracy <= TripAccumulator.maxHorizontalAccuracy,
                  now.timeIntervalSince(location.timestamp) <= 20 else { continue }
            probeBuffer.append(TrackPoint(location: location))
            if location.speed >= Self.autoStartSpeed {
                probeFastFixes += 1
            }
        }
        probeBuffer.removeAll { now.timeIntervalSince($0.timestamp) > 180 }

        if probeFastFixes >= Self.autoStartFixes {
            // 从第一次达到车速前 30 秒开始算，开头那一段不丢
            let firstFast = probeBuffer.first(where: { $0.speed >= Self.autoStartSpeed })?.timestamp ?? now
            let seed = probeBuffer.filter { $0.timestamp >= firstFast.addingTimeInterval(-30) }
            startRecording(trigger: .auto, startDate: seed.first?.timestamp ?? now, seed: seed)
        } else if now.timeIntervalSince(probeStart) > Self.probeDuration {
            endProbe()
        }
    }

    private func endProbeIfIdle() {
        if isProbing && !isRecording {
            endProbe()
        }
    }

    private func endProbe() {
        isProbing = false
        probeTimer?.invalidate()
        probeTimer = nil
        probeBuffer = []
        guard !isRecording else { return }
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        if AppSettings.autoDetectDriving {
            armGeofence(at: manager.location)
        }
    }

    private func startAutoStopTimer() {
        autoStopTimer?.invalidate()
        autoStopTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
            MainActor.assumeIsolated {
                TripRecorder.shared.autoStopIfIdle()
            }
        }
    }

    /// 自动开始的行程：停车超过 5 分钟就结束保存，停车之后（例如下车走路）的轨迹会去掉
    private func autoStopIfIdle() {
        guard isRecording, let current = state, current.autoStop == true else { return }
        let lastDriving = current.lastDrivingDate ?? current.startDate
        guard Date().timeIntervalSince(lastDriving) >= Self.autoStopAfter else { return }
        stopLocationServices()
        writer?.close()
        writer = nil
        let points = TrackStore.readPoints(for: current.id)
        finalizeTrimmed(state: current, points: points, until: lastDriving, note: "停车超过 5 分钟，自动结束")
        resetLiveState()
        updateAutoDetection()
    }

    @discardableResult
    private func finalizeTrimmed(state current: ActiveTripState,
                                 points: [TrackPoint],
                                 until: Date,
                                 note: String) -> StopOutcome {
        let kept = points.filter { $0.timestamp <= until.addingTimeInterval(5) }
        if kept.count != points.count {
            TrackStore.overwrite(current.id, points: kept)
        }
        var acc = TripAccumulator()
        for point in kept {
            acc.add(point)
        }
        return finalize(state: current, accumulator: acc, points: kept,
                        endDate: max(until, current.startDate), note: note)
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
        if didBootstrap {
            updateAutoDetection()
        }
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

    nonisolated func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        MainActor.assumeIsolated {
            TripRecorder.shared.beginProbe()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // kCLErrorLocationUnknown 是暂时性错误，忽略；权限被拒会走 didChangeAuthorization
        print("定位错误：\(error.localizedDescription)")
    }
}
