import SwiftUI
import CoreLocation
import UserNotifications

/// 首页醒目提示：定位权限不是「始终」、精确位置关闭、通知关闭
struct PermissionBanner: View {
    @ObservedObject private var recorder = TripRecorder.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var notificationStatus: UNAuthorizationStatus = .authorized

    private var hasLocationIssue: Bool {
        if !recorder.locationServicesEnabled { return true }
        switch recorder.authorizationStatus {
        case .notDetermined, .denied, .restricted, .authorizedWhenInUse:
            return true
        default:
            return recorder.accuracyAuthorization == .reducedAccuracy
        }
    }

    private var hasContent: Bool {
        hasLocationIssue || notificationStatus == .denied
    }

    var body: some View {
        VStack(spacing: 12) {
            locationBanner
            if notificationStatus == .denied {
                BannerCard(
                    icon: "bell.slash.fill",
                    tint: .orange,
                    title: "通知已关闭",
                    message: "无法收到「开始记录 / 行程已保存」和到期提醒的通知，不方便确认自动化是否运行。"
                ) {
                    Button("打开设置") { SystemSettings.open() }
                        .glassButtonStyle()
                }
            }
        }
        .padding(.bottom, hasContent ? Theme.spacing : 0)
        .task { await refreshNotifications() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                recorder.refreshAuthorization()
                Task { await refreshNotifications() }
            }
        }
    }

    @ViewBuilder
    private var locationBanner: some View {
        if !recorder.locationServicesEnabled {
            BannerCard(icon: "location.slash.fill", tint: .red, title: "定位服务已关闭",
                       message: "请到 设置 → 隐私与安全性 → 定位服务 打开定位，否则无法记录行程。") {
                Button("打开设置") { SystemSettings.open() }
                    .glassButtonStyle(prominent: true)
            }
        } else {
            switch recorder.authorizationStatus {
            case .notDetermined:
                BannerCard(icon: "location.circle.fill", tint: .blue, title: "需要定位权限",
                           message: "记录行程需要使用定位。先点「允许定位」，之后再改为「始终」。") {
                    Button("允许定位") { recorder.requestWhenInUseAuthorization() }
                        .glassButtonStyle(prominent: true)
                }
            case .denied, .restricted:
                BannerCard(icon: "location.slash.fill", tint: .red, title: "定位权限被拒绝",
                           message: "请到 设置 → 行车记录 → 位置，选择「始终」，并打开「精确位置」。") {
                    Button("打开设置") { SystemSettings.open() }
                        .glassButtonStyle(prominent: true)
                }
            case .authorizedWhenInUse:
                BannerCard(icon: "exclamationmark.triangle.fill", tint: .orange, title: "定位权限不是「始终」",
                           message: "当前为「使用 App 期间」，快捷指令无法在锁屏 / 后台自动开始记录。请改为「始终」。") {
                    HStack {
                        Button("改为始终") { recorder.requestAlwaysAuthorization() }
                            .glassButtonStyle(prominent: true)
                        Button("打开设置") { SystemSettings.open() }
                            .glassButtonStyle()
                    }
                }
            default:
                EmptyView()
            }
            if recorder.authorizationStatus != .denied,
               recorder.authorizationStatus != .notDetermined,
               recorder.accuracyAuthorization == .reducedAccuracy {
                BannerCard(icon: "scope", tint: .orange, title: "「精确位置」已关闭",
                           message: "模糊定位误差可达几公里，轨迹和里程都会不准。请到 设置 → 行车记录 → 位置 打开「精确位置」。") {
                    Button("打开设置") { SystemSettings.open() }
                        .glassButtonStyle(prominent: true)
                }
            }
        }
    }

    private func refreshNotifications() async {
        notificationStatus = await NotificationManager.shared.authorizationStatus()
    }
}

struct BannerCard<Actions: View>: View {
    let icon: String
    let tint: Color
    let title: String
    let message: String
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(tint)
                Text(title)
                    .font(.headline)
            }
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            actions()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 24, tint: tint.opacity(0.22))
    }
}
