import SwiftUI
import SwiftData
import CoreLocation

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @State private var databaseMessage: String?

    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("首页", systemImage: "speedometer") }
            TripListView()
                .tabItem { Label("行程", systemImage: "map") }
            FuelListView()
                .tabItem { Label("加油", systemImage: "fuelpump") }
            ExpenseListView()
                .tabItem { Label("费用", systemImage: "creditcard") }
            GarageView()
                .tabItem { Label("车辆/设置", systemImage: "car.2") }
        }
        .minimizeTabBarOnScroll()
        .tint(Theme.accent)
        .fontDesign(.rounded)
        .task {
            SeedData.ensureDefaults(context: context)
            TripRecorder.shared.bootstrap()
            NotificationManager.shared.requestAuthorizationIfNeeded()
            if TripRecorder.shared.authorizationStatus == .notDetermined {
                TripRecorder.shared.requestWhenInUseAuthorization()
            }
            databaseMessage = DataStore.shared.recoveryMessage
            ReminderEngine.rescheduleAll(context: context)
            await TripService.fillMissingAddresses(context: context)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                TripRecorder.shared.refreshAuthorization()
            }
        }
        .alert("数据库已重建",
               isPresented: Binding(get: { databaseMessage != nil }, set: { if !$0 { databaseMessage = nil } })) {
            Button("知道了", role: .cancel) { databaseMessage = nil }
        } message: {
            Text(databaseMessage ?? "")
        }
    }
}
