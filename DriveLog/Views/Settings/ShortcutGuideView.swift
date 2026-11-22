import SwiftUI

/// 快捷指令自动化设置步骤
struct ShortcutGuideView: View {
    @ObservedObject private var recorder = TripRecorder.shared

    var body: some View {
        List {
            Section {
                Text("连上 CarPlay 自动开始记录、断开自动停止并保存，靠的是 iOS「快捷指令」的个人自动化。需要新建两个自动化，只需设置一次。")
                    .font(.subheadline)
            }

            Section("准备") {
                GuideStep(number: 1, text: "定位权限：设置 → 行车记录 → 位置 → 选「始终」，并打开「精确位置」。")
                GuideStep(number: 2, text: "通知权限：设置 → 行车记录 → 通知 → 允许通知（用于确认自动化真的运行了）。")
                GuideStep(number: 3, text: "先手动打开一次本 App，完成上面两项授权。")
            }

            Section("自动化一：连接 CarPlay → 开始记录") {
                GuideStep(number: 1, text: "打开「快捷指令」App，点底部「自动化」。")
                GuideStep(number: 2, text: "点右上角「+」（第一次用是「新建自动化」/「创建个人自动化」）。")
                GuideStep(number: 3, text: "在列表里选择「CarPlay」。")
                GuideStep(number: 4, text: "勾选「连接」，选择「立即运行」，（可选）关闭「运行时通知」，点「下一步」。")
                GuideStep(number: 5, text: "点「新建空白自动化」→「添加操作」，搜索「行车记录」，选择「开始记录行程」。")
                GuideStep(number: 6, text: "点右上角「完成」。")
            }

            Section("自动化二：断开 CarPlay → 停止并保存") {
                GuideStep(number: 1, text: "同样在「自动化」里点「+」→ 选择「CarPlay」。")
                GuideStep(number: 2, text: "这次勾选「断开连接」，选择「立即运行」，点「下一步」。")
                GuideStep(number: 3, text: "「新建空白自动化」→「添加操作」→ 搜索「行车记录」→ 选择「停止记录并保存」。")
                GuideStep(number: 4, text: "点「完成」。")
            }

            Section("如何确认生效") {
                GuideStep(number: 1, text: "连上 CarPlay 后会收到通知「开始记录行程」。")
                GuideStep(number: 2, text: "断开后会收到通知「行程已保存：12.3 km · 18分 · 最高 98 km/h」。")
                GuideStep(number: 3, text: "短于 100 m 的行程（例如停着插了一下线）会自动丢弃，并通知「行程过短，未保存」。")
                GuideStep(number: 4, text: "重复触发是安全的：已经在记录时再触发开始会被忽略；没在记录时触发停止也会被忽略。")
            }

            Section {
                if recorder.isRecording {
                    Button(role: .destructive) {
                        recorder.stopRecording(trigger: .manual)
                    } label: {
                        Label("测试：停止记录并保存", systemImage: "stop.circle")
                    }
                } else {
                    Button {
                        recorder.startRecording(trigger: .manual)
                    } label: {
                        Label("测试：开始记录", systemImage: "play.circle")
                    }
                }
            } header: {
                Text("手动测试")
            } footer: {
                Text("也可以在「快捷指令」App 里直接运行「开始记录行程」/「停止记录并保存」来测试。")
            }
        }
        .navigationTitle("快捷指令自动化")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct GuideStep: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.accentColor))
            Text(text)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
    }
}
