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

/// 列表行里用的「磨砂玻璃」卡片：
/// 系统 List 会把每行裁剪在行边界内，真正的 Liquid Glass 自带阴影，被裁掉后会出现灰色硬边。
/// 这里用材质 + 浅色调 + 高光描边做出玻璃质感，不带外阴影。
struct FrostedCardModifier: ViewModifier {
    var cornerRadius: CGFloat = 26
    var tint: Color? = nil
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let dark = colorScheme == .dark
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return content
            .background {
                ZStack {
                    shape.fill(.ultraThinMaterial)
                    if let tint {
                        shape.fill(tint.opacity(dark ? 0.10 : 0.07))
                    }
                    shape.fill(LinearGradient(colors: [Color.white.opacity(dark ? 0.06 : 0.45),
                                                       Color.white.opacity(0)],
                                              startPoint: .top,
                                              endPoint: .center))
                    shape.strokeBorder(LinearGradient(colors: [Color.white.opacity(dark ? 0.28 : 0.9),
                                                               Color.white.opacity(dark ? 0.06 : 0.25)],
                                                      startPoint: .top,
                                                      endPoint: .bottom),
                                       lineWidth: 1)
                }
            }
    }
}

extension View {
    func frostedCard(cornerRadius: CGFloat = 26, tint: Color? = nil) -> some View {
        modifier(FrostedCardModifier(cornerRadius: cornerRadius, tint: tint))
    }

    /// 隐藏导航栏的页面：内容滚到状态栏下面时，状态栏区域做模糊处理
    @ViewBuilder
    func statusBarBackdrop() -> some View {
        if #available(iOS 26.0, *) {
            self.safeAreaBar(edge: .top) {
                Color.clear.frame(height: 0)
            }
        } else {
            self.safeAreaInset(edge: .top, spacing: 0) {
                Color.clear
                    .frame(height: 0)
                    .background(.ultraThinMaterial, ignoresSafeAreaEdges: .top)
            }
        }
    }
}

/// 柔和的彩色背景：玻璃需要有内容在后面才看得出折射效果。
/// 浅色：近白的冷灰底；深色：深海军蓝底，再叠几团模糊的品牌色光斑。
struct AppBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let dark = colorScheme == .dark
        ZStack {
            (dark ? Color(red: 0.035, green: 0.05, blue: 0.10) : Color(red: 0.948, green: 0.958, blue: 0.985))
            GeometryReader { proxy in
                let w = proxy.size.width
                let h = proxy.size.height
                ZStack {
                    glow(Theme.accent, opacity: dark ? 0.38 : 0.26, size: w * 1.05)
                        .position(x: w * 0.08, y: h * 0.04)
                    glow(Theme.accentSecondary, opacity: dark ? 0.24 : 0.20, size: w * 0.85)
                        .position(x: w * 0.98, y: h * 0.30)
                    glow(Color(red: 0.55, green: 0.36, blue: 0.95), opacity: dark ? 0.26 : 0.14, size: w * 0.95)
                        .position(x: w * 0.10, y: h * 0.72)
                    glow(Theme.fuel, opacity: dark ? 0.14 : 0.12, size: w * 0.75)
                        .position(x: w * 0.92, y: h * 0.98)
                }
            }
        }
        .ignoresSafeArea()
    }

    private func glow(_ color: Color, opacity: Double, size: CGFloat) -> some View {
        Circle()
            .fill(color.opacity(opacity))
            .frame(width: size, height: size)
            .blur(radius: size * 0.22)
    }
}
