import AppIntents

/// 「开始记录行程」：给快捷指令的 CarPlay「连接」自动化用。
/// openAppWhenRun = false：不打开 App，在后台（锁屏时也可以）启动记录。
struct StartTripIntent: AppIntent {
    static let title: LocalizedStringResource = "开始记录行程"
    static let description = IntentDescription("在后台开始记录 GPS 行程。已经在记录时再次运行会被忽略。适合放在「CarPlay 连接」自动化里。")
    static let openAppWhenRun: Bool = false
    static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        // 已经在记录时会返回 .alreadyRecording，直接忽略
        TripRecorder.shared.startRecording(trigger: .shortcut)
        return .result()
    }
}

/// 「停止记录并保存」：给快捷指令的 CarPlay「断开连接」自动化用。
struct StopTripIntent: AppIntent {
    static let title: LocalizedStringResource = "停止记录并保存"
    static let description = IntentDescription("停止当前行程记录并保存。没有在记录时运行会被忽略。适合放在「CarPlay 断开连接」自动化里。")
    static let openAppWhenRun: Bool = false
    static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        // 没在记录时返回 .notRecording，直接忽略
        TripRecorder.shared.stopRecording(trigger: .shortcut)
        return .result()
    }
}
