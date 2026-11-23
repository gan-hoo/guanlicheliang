import Foundation

struct CurrencyOption: Identifiable, Hashable {
    let code: String
    let symbol: String
    let name: String
    let decimals: Int
    var id: String { code }
}

/// 简单的全局设置（UserDefaults），视图里用 @AppStorage 读同一个 key
enum AppSettings {
    static let currentVehicleKey = "currentVehicleID"
    static let currencyKey = "currencyCode"
    static let didSeedCategoriesKey = "didSeedCategories"
    static let didRequestLocationKey = "didRequestLocation"
    static let autoDetectKey = "autoDetectDriving"

    static let defaultCurrency = "AUD"

    static let currencies: [CurrencyOption] = [
        CurrencyOption(code: "AUD", symbol: "$", name: "澳元", decimals: 2),
        CurrencyOption(code: "CNY", symbol: "¥", name: "人民币", decimals: 2),
        CurrencyOption(code: "USD", symbol: "US$", name: "美元", decimals: 2),
        CurrencyOption(code: "NZD", symbol: "NZ$", name: "新西兰元", decimals: 2),
        CurrencyOption(code: "HKD", symbol: "HK$", name: "港币", decimals: 2),
        CurrencyOption(code: "SGD", symbol: "S$", name: "新加坡元", decimals: 2),
        CurrencyOption(code: "CAD", symbol: "C$", name: "加元", decimals: 2),
        CurrencyOption(code: "EUR", symbol: "€", name: "欧元", decimals: 2),
        CurrencyOption(code: "GBP", symbol: "£", name: "英镑", decimals: 2),
        CurrencyOption(code: "JPY", symbol: "¥", name: "日元", decimals: 0)
    ]

    static var currentVehicleID: UUID? {
        get {
            guard let s = UserDefaults.standard.string(forKey: currentVehicleKey) else { return nil }
            return UUID(uuidString: s)
        }
        set {
            UserDefaults.standard.set(newValue?.uuidString ?? "", forKey: currentVehicleKey)
        }
    }

    /// 自动检测驾驶（默认开启）
    static var autoDetectDriving: Bool {
        UserDefaults.standard.object(forKey: autoDetectKey) as? Bool ?? true
    }

    static var currencyCode: String {
        get { UserDefaults.standard.string(forKey: currencyKey) ?? defaultCurrency }
        set { UserDefaults.standard.set(newValue, forKey: currencyKey) }
    }

    static var currency: CurrencyOption {
        let code = currencyCode
        return currencies.first(where: { $0.code == code }) ?? currencies[0]
    }
}
