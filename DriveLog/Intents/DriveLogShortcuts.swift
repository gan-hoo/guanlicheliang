import AppIntents

/// 让两个动作在「快捷指令」里好找（App 快捷指令 + 搜索「行车记录」）
struct DriveLogShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartTripIntent(),
            phrases: [
                "用\(.applicationName)开始记录行程",
                "\(.applicationName)开始记录"
            ],
            shortTitle: "开始记录行程",
            systemImageName: "car.fill"
        )
        AppShortcut(
            intent: StopTripIntent(),
            phrases: [
                "用\(.applicationName)停止记录并保存",
                "\(.applicationName)停止记录"
            ],
            shortTitle: "停止记录并保存",
            systemImageName: "stop.circle.fill"
        )
    }
}
