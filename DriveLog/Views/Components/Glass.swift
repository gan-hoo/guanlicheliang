import SwiftUI

// Apple Liquid Glass（iOS 26）。
// 系统控件（Tab 栏、导航栏、工具栏、弹出面板）用 iOS 26 SDK 编译后自动变成玻璃；
// 这里给自定义的卡片、按钮、地图浮层加上玻璃效果。
// iOS 17–25 上自动退回为毛玻璃材质。

@available(iOS 26.0, *)
enum GlassStyle {
    static func make(tint: Color?, interactive: Bool) -> Glass {
        var glass = Glass.regular
        if let tint {
            glass = glass.tint(tint)
        }
        if interactive {
            glass = glass.interactive()
        }
        return glass
    }
}

extension View {
    /// 玻璃卡片
    @ViewBuilder
    func glassCard(cornerRadius: CGFloat = 26, tint: Color? = nil, interactive: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(GlassStyle.make(tint: tint, interactive: interactive),
                             in: .rect(cornerRadius: cornerRadius))
        } else {
            self.background {
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.regularMaterial)
                    if let tint {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(tint.opacity(0.12))
                    }
                }
            }
        }
    }

    /// 玻璃胶囊（地图图例等浮层）
    @ViewBuilder
    func glassCapsule(tint: Color? = nil, interactive: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(GlassStyle.make(tint: tint, interactive: interactive), in: .capsule)
        } else {
            self.background(.regularMaterial, in: Capsule())
        }
    }

    /// 玻璃圆形按钮（地图上的展开按钮等）
    @ViewBuilder
    func glassCircle(tint: Color? = nil) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(GlassStyle.make(tint: tint, interactive: true), in: .circle)
        } else {
            self.background(.regularMaterial, in: Circle())
        }
    }

    /// 玻璃按钮：prominent = 实色玻璃（主要操作），否则为透明玻璃
    @ViewBuilder
    func glassButtonStyle(prominent: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            if prominent {
                self.buttonStyle(.glassProminent)
            } else {
                self.buttonStyle(.glass)
            }
        } else {
            if prominent {
                self.buttonStyle(.borderedProminent)
            } else {
                self.buttonStyle(.bordered)
            }
        }
    }

    /// 向下滚动时 Tab 栏缩小（iOS 26）
    @ViewBuilder
    func minimizeTabBarOnScroll() -> some View {
        if #available(iOS 26.0, *) {
            self.tabBarMinimizeBehavior(.onScrollDown)
        } else {
            self
        }
    }

    /// 列表页使用带色彩的背景，让玻璃导航栏 / Tab 栏透出颜色
    func appBackground() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background { AppBackground() }
    }
}

/// 柔和的彩色背景：玻璃需要有内容在后面才看得出折射效果
struct AppBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let strength = colorScheme == .dark ? 0.55 : 1.0
        ZStack {
            Color(uiColor: .systemGroupedBackground)
            LinearGradient(colors: [Color.blue.opacity(0.16 * strength),
                                    Color.teal.opacity(0.08 * strength),
                                    Color.purple.opacity(0.12 * strength)],
                           startPoint: .topLeading,
                           endPoint: .bottomTrailing)
            GeometryReader { proxy in
                let w = proxy.size.width
                let h = proxy.size.height
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.30 * strength))
                        .frame(width: w * 0.9, height: w * 0.9)
                        .blur(radius: 70)
                        .position(x: w * 0.15, y: h * 0.08)
                    Circle()
                        .fill(Color.orange.opacity(0.20 * strength))
                        .frame(width: w * 0.75, height: w * 0.75)
                        .blur(radius: 80)
                        .position(x: w * 0.95, y: h * 0.42)
                    Circle()
                        .fill(Color.purple.opacity(0.22 * strength))
                        .frame(width: w * 0.85, height: w * 0.85)
                        .blur(radius: 80)
                        .position(x: w * 0.2, y: h * 0.85)
                }
            }
        }
        .ignoresSafeArea()
    }
}
