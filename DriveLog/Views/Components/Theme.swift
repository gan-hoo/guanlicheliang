import SwiftUI
import UIKit

/// 统一的配色与尺寸。每种数据固定一种颜色，全 App 一致：
/// 距离 = 蓝，时间 = 靛，速度 = 橙，最高速 = 红，海拔 = 绿，花费 = 粉，燃油 = 琥珀
enum Theme {
    static let accent = Color(red: 0.18, green: 0.46, blue: 1.0)
    static let accentSecondary = Color(red: 0.07, green: 0.72, blue: 0.80)

    static let distance = Color(red: 0.18, green: 0.46, blue: 1.0)
    static let duration = Color(red: 0.43, green: 0.36, blue: 0.96)
    static let speed = Color(red: 1.0, green: 0.55, blue: 0.12)
    static let maxSpeed = Color(red: 0.96, green: 0.27, blue: 0.30)
    static let altitude = Color(red: 0.16, green: 0.71, blue: 0.45)
    static let money = Color(red: 0.94, green: 0.29, blue: 0.55)
    static let fuel = Color(red: 1.0, green: 0.62, blue: 0.08)
    static let record = Color(red: 0.97, green: 0.22, blue: 0.27)
    /// 首页 START 按钮：比主色柔和的蓝（饱和度更低，不刺眼）
    static let startButton = Color(red: 0.25, green: 0.43, blue: 0.80)

    /// 白色背景上的列表行底色（让分组的圆角边框显示出来）
    static let rowFill = Color(uiColor: .secondarySystemBackground)

    /// 每页第一张玻璃卡片和标题之间的距离
    static let firstCardTopSpacing: CGFloat = 14

    static let cardRadius: CGFloat = 26
    static let tileRadius: CGFloat = 16
    static let spacing: CGFloat = 14

    static var brandGradient: LinearGradient {
        LinearGradient(colors: [accent, accentSecondary], startPoint: .leading, endPoint: .trailing)
    }

    static var fuelGradient: LinearGradient {
        LinearGradient(colors: [fuel, Color(red: 1.0, green: 0.40, blue: 0.20)], startPoint: .leading, endPoint: .trailing)
    }

    static var moneyGradient: LinearGradient {
        LinearGradient(colors: [money, Color(red: 0.62, green: 0.32, blue: 0.95)], startPoint: .leading, endPoint: .trailing)
    }

    /// 弹簧动画（统一手感）
    static let spring = Animation.spring(response: 0.5, dampingFraction: 0.86)
}

extension Font {
    /// 数字用圆体
    static func numeric(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

/// 圆形彩色底的小图标
struct MetricIcon: View {
    let systemName: String
    let tint: Color
    var size: CGFloat = 28

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.46, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(Circle().fill(tint.opacity(0.16)))
    }
}

/// 小号「图标 + 文字」指标
struct MetricLabel: View {
    let text: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
            Text(text)
                .foregroundStyle(.secondary)
        }
        .font(.caption)
        .lineLimit(1)
    }
}

/// 机械里程表样式的数字
struct OdometerView: View {
    let value: Double
    var digits: Int = 6
    var digitWidth: CGFloat = 22
    var digitHeight: CGFloat = 32

    var body: some View {
        let number = max(0, Int(value.rounded()))
        let text = String(number)
        let leadingZeros = max(0, digits - text.count)
        let padded = String(repeating: "0", count: leadingZeros) + text
        HStack(spacing: 3) {
            ForEach(Array(padded.enumerated()), id: \.offset) { item in
                Text(String(item.element))
                    .font(.system(size: digitHeight * 0.62, weight: .semibold, design: .monospaced))
                    .foregroundStyle(item.offset < leadingZeros ? Color.white.opacity(0.3) : Color.white)
                    .contentTransition(.numericText())
                    .frame(width: digitWidth, height: digitHeight)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(LinearGradient(colors: [Color(white: 0.20), Color(white: 0.06)],
                                                 startPoint: .top,
                                                 endPoint: .bottom))
                    )
                    .overlay(
                        Rectangle()
                            .fill(Color.black.opacity(0.35))
                            .frame(height: 1)
                    )
            }
            Text("km")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
        }
        .animation(.snappy, value: number)
    }
}

/// 日历样式的日期小方块（颜色按行程的平均速度区间）
struct DateBadge: View {
    let date: Date
    let tint: Color

    var body: some View {
        VStack(spacing: 0) {
            Text(Fmt.weekday.string(from: date))
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.85))
            Text("\(Calendar.current.component(.day, from: date))")
                .font(.numeric(20, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: 46, height: 50)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(LinearGradient(colors: [tint, tint.opacity(0.72)], startPoint: .top, endPoint: .bottom))
        )
        .shadow(color: tint.opacity(0.35), radius: 6, y: 3)
    }
}

/// 卡片标题行
struct CardHeader<Trailing: View>: View {
    let title: String
    var systemImage: String? = nil
    var tint: Color = Theme.accent
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 8) {
            if let systemImage {
                MetricIcon(systemName: systemImage, tint: tint, size: 26)
            }
            Text(title)
                .font(.headline)
            Spacer()
            trailing()
        }
    }
}

extension CardHeader where Trailing == EmptyView {
    init(title: String, systemImage: String? = nil, tint: Color = Theme.accent) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
        self.trailing = { EmptyView() }
    }
}

extension View {
    /// 滚动时卡片轻微缩放、变淡，增加层次感
    func cardScrollEffect() -> some View {
        scrollTransition(.interactive) { content, phase in
            content
                .opacity(phase.isIdentity ? 1 : 0.7)
                .scaleEffect(phase.isIdentity ? 1 : 0.965)
                .blur(radius: phase.isIdentity ? 0 : 0.6)
        }
    }

    /// 在列表顶部放一张真正的液态玻璃卡片。
    /// 放在分区标题里：列表的行会被裁剪成圆角，会切掉玻璃的阴影；分区标题不会。
    func glassListHeader(topSpacing: CGFloat = 0) -> some View {
        self
            .card()
            .listHeaderContainer(topSpacing: topSpacing)
    }

    /// 把已经是玻璃卡片的视图放进分区标题（首页和其他页用同一套布局，位置一致）
    func listHeaderContainer(topSpacing: CGFloat = 0) -> some View {
        self
            .foregroundStyle(.primary)
            .textCase(nil)
            .padding(.top, topSpacing)
            .padding(.bottom, 4)
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
    }
}
