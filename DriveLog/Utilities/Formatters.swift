import Foundation

/// 全中文格式化：km/h、km、L/100km
enum Fmt {
    static let zhLocale = Locale(identifier: "zh_CN")

    private static func makeFormatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = zhLocale
        f.dateFormat = format
        return f
    }

    static let dateFull = makeFormatter("yyyy年M月d日")
    static let dateShort = makeFormatter("M月d日")
    static let dateTimeShort = makeFormatter("M月d日 HH:mm")
    static let dateTimeFull = makeFormatter("yyyy年M月d日 HH:mm")
    static let time = makeFormatter("HH:mm")
    static let monthTitle = makeFormatter("yyyy年M月")
    static let monthShort = makeFormatter("M月")
    static let yearTitle = makeFormatter("yyyy年")
    static let weekday = makeFormatter("EEE")
    static let fileStamp: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd_HHmm"
        return f
    }()

    private static let groupedFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = ","
        f.decimalSeparator = "."
        f.usesGroupingSeparator = true
        return f
    }()

    static func grouped(_ value: Double, decimals: Int) -> String {
        groupedFormatter.minimumFractionDigits = decimals
        groupedFormatter.maximumFractionDigits = decimals
        return groupedFormatter.string(from: NSNumber(value: value)) ?? String(format: "%.\(decimals)f", value)
    }

    /// 米 → "850 m" / "12.3 km"
    static func distance(_ meters: Double) -> String {
        if meters < 1000 { return "\(Int(meters.rounded())) m" }
        return "\(grouped(meters / 1000, decimals: 1)) km"
    }

    static func km(_ km: Double, decimals: Int = 1) -> String {
        "\(grouped(km, decimals: decimals)) km"
    }

    /// 里程表读数 "12,345 km"
    static func odometer(_ km: Double) -> String {
        "\(grouped(km.rounded(), decimals: 0)) km"
    }

    static func kmh(_ metersPerSecond: Double) -> Double { metersPerSecond * 3.6 }

    static func speed(_ metersPerSecond: Double) -> String {
        "\(Int((max(0, metersPerSecond) * 3.6).rounded())) km/h"
    }

    /// "1小时23分" / "18分" / "45秒"
    static func duration(_ seconds: Double) -> String {
        let total = Int(max(0, seconds).rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return "\(h)小时\(m)分" }
        if m > 0 { return "\(m)分" }
        return "\(s)秒"
    }

    /// "1:02:03"
    static func clock(_ seconds: Double) -> String {
        let total = Int(max(0, seconds))
        return String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }

    static func money(_ value: Double) -> String {
        let currency = AppSettings.currency
        let sign = value < 0 ? "-" : ""
        return "\(sign)\(currency.symbol)\(grouped(abs(value), decimals: currency.decimals))"
    }

    static var currencySymbol: String { AppSettings.currency.symbol }

    /// 油价（每升）保留 3 位小数
    static func unitPrice(_ value: Double) -> String {
        "\(AppSettings.currency.symbol)\(String(format: "%.3f", value))"
    }

    static func economy(_ litersPer100km: Double?) -> String {
        guard let v = litersPer100km, v.isFinite else { return "—" }
        return String(format: "%.1f L/100km", v)
    }

    static func liters(_ v: Double) -> String {
        String(format: "%.2f L", v)
    }

    static func number(_ v: Double, decimals: Int = 1) -> String {
        grouped(v, decimals: decimals)
    }

    /// 编辑框里显示的数字（不带分组）
    static func plain(_ v: Double?, decimals: Int) -> String {
        guard let v else { return "" }
        var s = String(format: "%.\(decimals)f", v)
        if decimals > 0, s.contains(".") {
            while s.hasSuffix("0") { s.removeLast() }
            if s.hasSuffix(".") { s.removeLast() }
        }
        return s
    }

    static func altitude(_ meters: Double?) -> String {
        guard let meters else { return "—" }
        return "\(Int(meters.rounded())) m"
    }
}

enum NumberParser {
    /// 兼容 "1,5" 和 "1.5"
    static func double(_ text: String) -> Double? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: ".")
        guard !t.isEmpty else { return nil }
        return Double(t)
    }

    static func int(_ text: String) -> Int? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        return Int(t)
    }
}
