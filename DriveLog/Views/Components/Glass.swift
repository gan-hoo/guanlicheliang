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

/// 页面背景：白色（深色模式下跟随系统为黑色）
struct AppBackground: View {
    var body: some View {
        Color(uiColor: .systemBackground)
            .ignoresSafeArea()
    }
}
