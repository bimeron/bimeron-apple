import SwiftUI

enum AppPalette {
    static let blue = Color(red: 40 / 255, green: 123 / 255, blue: 1)
    static let blueDisabled = Color(red: 144 / 255, green: 169 / 255, blue: 203 / 255)
    static let blueDisabledButton = Color(red: 75 / 255, green: 106 / 255, blue: 157 / 255)

    static func canvas(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(nsColor: .windowBackgroundColor) : Color(red: 0.965, green: 0.973, blue: 0.992)
    }

    static func sidebar(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(nsColor: .underPageBackgroundColor) : Color(red: 0.940, green: 0.953, blue: 0.982)
    }

    static func surface(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(nsColor: .controlBackgroundColor) : .white
    }

    static func border(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? .white.opacity(0.10) : Color(red: 0.890, green: 0.914, blue: 0.957)
    }
}
