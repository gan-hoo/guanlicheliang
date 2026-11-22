import SwiftUI
import SwiftData

@main
struct DriveLogApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.locale, Locale(identifier: "zh_CN"))
        }
        .modelContainer(DataStore.shared.container)
    }
}
