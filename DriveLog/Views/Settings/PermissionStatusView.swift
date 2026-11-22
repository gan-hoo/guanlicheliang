import SwiftUI
import CoreLocation
import UserNotifications

struct PermissionStatusView: View {
    @ObservedObject private var recorder = TripRecorder.shared
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined

    var body: some View {
        List {
            Section {
                StatusRow(title: "定位服务", ok: recorder.locationServicesEnabled,
                          value: recorder.locationServicesEnabled ? "已开启" : "已关闭")
                StatusRow(title: "定位权限", ok: recorder.authorizationStatus == .authorizedAlways,
                          value: authorizationText)
                StatusRow(title: "精确位置", ok: recorder.accuracyAuthorization == .fullAccuracy,
                          value: recorder.accuracyAuthorization == .fullAccuracy ? "已打开" : "已关闭")
                StatusRow(title: "通知", ok: notificationStatus == .authorized || notificationStatus == .provisional,
                          value: notificationText)
            } footer: {
                Text("后台自动开始记录需要：定位「始终」+ 精确位置。")
            }

            Section {
                if recorder.authorizationStatus == .notDetermined {
                    Button("允许定位") { recorder.requestWhenInUseAuthorization() }
                }
                if recorder.authorizationStatus == .authorizedWhenInUse {
                    Button("申请改为「始终」") { recorder.requestAlwaysAuthorization() }
                }
                if notificationStatus == .notDetermined {
                    Button("允许通知") { NotificationManager.shared.requestAuthorizationIfNeeded() }
                }
                Button("打开系统设置") { SystemSettings.open() }
            }
        }
        .navigationTitle("权限")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            recorder.refreshAuthorization()
            notificationStatus = await NotificationManager.shared.authorizationStatus()
        }
    }

    private var authorizationText: String {
        switch recorder.authorizationStatus {
        case .authorizedAlways: return "始终"
        case .authorizedWhenInUse: return "使用 App 期间"
        case .denied: return "已拒绝"
        case .restricted: return "受限制"
        case .notDetermined: return "未设置"
        @unknown default: return "未知"
        }
    }

    private var notificationText: String {
        switch notificationStatus {
        case .authorized: return "已允许"
        case .provisional: return "临时允许"
        case .ephemeral: return "临时"
        case .denied: return "已关闭"
        case .notDetermined: return "未设置"
        @unknown default: return "未知"
        }
    }
}

private struct StatusRow: View {
    let title: String
    let ok: Bool
    let value: String

    var body: some View {
        HStack {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(ok ? Color.green : Color.orange)
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
    }
}
