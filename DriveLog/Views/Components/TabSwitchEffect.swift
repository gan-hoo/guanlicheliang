import SwiftUI

/// 底部的 5 个 Tab
enum AppTab: Hashable {
    case home, trips, fuel, expenses, garage
}

private struct SelectedTabKey: EnvironmentKey {
    static let defaultValue: AppTab = .home
}

extension EnvironmentValues {
    /// 当前选中的 Tab
    var selectedTab: AppTab {
        get { self[SelectedTabKey.self] }
        set { self[SelectedTabKey.self] = newValue }
    }
}

/// 切换到这个 Tab 时，页面内容轻轻上浮淡入（标题栏和背景不动）。
/// 只在切换 Tab 时触发，从详情页返回时不会重复播放。
struct TabSwitchEffect: ViewModifier {
    let tab: AppTab
    @Environment(\.selectedTab) private var selectedTab
    @State private var shown = true

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 14)
            .onChange(of: selectedTab) { _, newTab in
                if newTab == tab {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.9)) {
                        shown = true
                    }
                } else {
                    shown = false
                }
            }
    }
}

extension View {
    func tabSwitchEffect(_ tab: AppTab) -> some View {
        modifier(TabSwitchEffect(tab: tab))
    }
}
