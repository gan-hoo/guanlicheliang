import Foundation

/// 燃油类型（存储用稳定的 rawValue，显示用 displayName）
enum FuelType: String, CaseIterable, Identifiable, Codable {
    case ulp91 = "91"
    case ulp95 = "95"
    case ulp98 = "98"
    case e10 = "E10"
    case diesel = "diesel"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ulp91: return "91"
        case .ulp95: return "95"
        case .ulp98: return "98"
        case .e10: return "E10"
        case .diesel: return "柴油"
        }
    }
}
