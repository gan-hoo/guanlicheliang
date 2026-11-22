import SwiftUI

/// 行程页列表卡的设计规范（只做浅色模式）
enum TripSpec {
    /// 主色 #DB7042
    static let primary = Color(red: 219 / 255, green: 112 / 255, blue: 66 / 255)
    /// 图标底块 #F9EDE7
    static let iconTile = Color(red: 249 / 255, green: 237 / 255, blue: 231 / 255)
    /// 主要文字 #09090B
    static let textPrimary = Color(red: 9 / 255, green: 9 / 255, blue: 11 / 255)
    /// 次要文字 #71717A
    static let textSecondary = Color(red: 113 / 255, green: 113 / 255, blue: 122 / 255)
    /// 提示语 #52525B
    static let hint = Color(red: 82 / 255, green: 82 / 255, blue: 91 / 255)
    /// 箭头 #A1A1AA
    static let chevron = Color(red: 161 / 255, green: 161 / 255, blue: 170 / 255)
    /// 描边、分隔线 #E4E4E7
    static let border = Color(red: 228 / 255, green: 228 / 255, blue: 231 / 255)

    static let cardRadius: CGFloat = 24
    static let horizontalPadding: CGFloat = 16
}

/// 列表卡：头部 + 若干行，行与行之间用分隔线
struct TripListCard<Rows: View>: View {
    let icon: String
    let title: String
    let subtitle: String
    @ViewBuilder var rows: () -> Rows

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 头部：上边距 18，左右 16；和第一行之间不加分隔线，间距 16
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(TripSpec.primary)
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(TripSpec.iconTile)
                    )
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(TripSpec.textPrimary)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .monospacedDigit()
                        .foregroundStyle(TripSpec.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 18)
            .padding(.horizontal, TripSpec.horizontalPadding)
            .padding(.bottom, 16)

            rows()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: TripSpec.cardRadius, style: .continuous)
                .fill(Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: TripSpec.cardRadius, style: .continuous)
                .strokeBorder(TripSpec.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: TripSpec.cardRadius, style: .continuous))
    }
}

/// 列表卡里的一行（行高约 57：上下内边距 12）
struct TripListRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let value: String
    var subValue: String? = nil

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(TripSpec.primary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(TripSpec.textPrimary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(TripSpec.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            // 没有副数值时，主数值在行里垂直居中
            VStack(alignment: .trailing, spacing: 4) {
                Text(value)
                    .font(.system(size: 15, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(TripSpec.textPrimary)
                    .lineLimit(1)
                if let subValue {
                    Text(subValue)
                        .font(.system(size: 12))
                        .monospacedDigit()
                        .foregroundStyle(TripSpec.textSecondary)
                        .lineLimit(1)
                }
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(TripSpec.chevron)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, TripSpec.horizontalPadding)
        .contentShape(Rectangle())
    }
}

/// 分隔线：1pt，左右各缩进 16
struct TripListDivider: View {
    var body: some View {
        Rectangle()
            .fill(TripSpec.border)
            .frame(height: 1)
            .padding(.horizontal, TripSpec.horizontalPadding)
    }
}

/// 行程页的数字格式：数字和单位之间留一个空格
enum TripSpecFormat {
    static func duration(_ seconds: Double) -> String {
        let total = Int(max(0, seconds).rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return "\(h) 小时 \(m) 分" }
        if m > 0 { return "\(m) 分" }
        return "\(s) 秒"
    }
}
