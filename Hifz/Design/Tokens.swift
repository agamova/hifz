import SwiftUI
import UIKit

// Цвета и шрифты из docs/design/word-card.md и docs/design/screens-v2.md.

extension Color {
    init(light: UInt32, dark: UInt32) {
        self = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
    }

    static let pageBg = Color(light: 0xF4F1EA, dark: 0x000000)
    static let cardBg = Color(light: 0xFFFDF8, dark: 0x1C1C1E)
    static let cardStroke = Color(light: 0xE6E1D6, dark: 0x2C2C2E)
    static let ink = Color(light: 0x1C1C1E, dark: 0xF2F2F7)
    static let inkDim = Color(light: 0x8A8780, dark: 0x8E8E93)
    static let inkSecondary = Color(light: 0x6B6862, dark: 0x98989F)
    static let focusNeutral = Color(light: 0xECE8E0, dark: 0x2C2C2E)
    static let segPrefix = Color(light: 0x7B4B94, dark: 0xC9A3DE)
    static let segSuffix = Color(light: 0xA34E2A, dark: 0xE7A07F)
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

extension Font {
    /// Amiri Quran, масштабируется вместе с Dynamic Type.
    static func quran(_ size: CGFloat, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom("Amiri Quran", size: size, relativeTo: style)
    }
}

enum Familiarity: Equatable {
    case new, sameForm, sameLemma, sameRoot

    /// Чем больше, тем знакомее.
    var rank: Int {
        switch self {
        case .new: 0
        case .sameRoot: 1
        case .sameLemma: 2
        case .sameForm: 3
        }
    }

    var background: Color? {
        switch self {
        case .new: nil
        case .sameForm: Color(light: 0xDCEFE7, dark: 0x1F3A31)
        case .sameLemma: Color(light: 0xDDE8F5, dark: 0x1E2F44)
        case .sameRoot: Color(light: 0xF4E8D2, dark: 0x3A2F1C)
        }
    }

    var line: Color {
        switch self {
        case .new: .clear
        case .sameForm: Color(light: 0x2F7D62, dark: 0x6FC2A0)
        case .sameLemma: Color(light: 0x3A6EA5, dark: 0x8DB4E2)
        case .sameRoot: Color(light: 0x9A6B1F, dark: 0xD9B26F)
        }
    }

    var dash: [CGFloat] {
        switch self {
        case .sameLemma: [6, 4]
        case .sameRoot: [0.1, 5]
        default: []
        }
    }

    var title: String {
        switch self {
        case .new: "Новое"
        case .sameForm: "Та же форма"
        case .sameLemma: "Та же лемма"
        case .sameRoot: "Тот же корень"
        }
    }

    var symbol: String {
        switch self {
        case .new: "circle.dashed"
        case .sameForm: "equal.circle"
        case .sameLemma: "arrow.triangle.branch"
        case .sameRoot: "circle.grid.2x1"
        }
    }
}
