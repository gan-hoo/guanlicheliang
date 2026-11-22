import UIKit

/// 无论是用户打开、快捷指令在后台拉起、还是 significant location change 唤醒，
/// 都会走 didFinishLaunching：在这里恢复未收尾的行程。
@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        NotificationManager.shared.configure()
        _ = DataStore.shared
        TripRecorder.shared.bootstrap()
        return true
    }
}
