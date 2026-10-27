import SwiftUI
import UIKit

/// Sinag brand tokens. Used only by the Sinag account screens; WLED device screens keep their look.
enum SinagColor {
    static let signalGold = Color(hex: 0xE4A82E)
    static let lanternNavy = Color(hex: 0x122340)
    static let goldTint = Color(hex: 0xF3C875)
    static let paper = Color(hex: 0xFAF7EF)
    static let slate = Color(hex: 0x5B6275)
    static let mutedOnDark = Color(hex: 0xB7C0D4)
    static let darkFieldFill = Color(hex: 0x1C3157)

    /// Paper in light mode, Lantern Navy in dark mode.
    static let background = adaptive(light: 0xFAF7EF, dark: 0x122340)
    /// Lantern Navy text on Paper, Paper text on navy.
    static let text = adaptive(light: 0x122340, dark: 0xFAF7EF)
    /// Slate on Paper, #B7C0D4 on navy.
    static let muted = adaptive(light: 0x5B6275, dark: 0xB7C0D4)
    /// Tagline: Slate on Paper, Gold Tint on navy (never gold text on Paper).
    static let tagline = adaptive(light: 0x5B6275, dark: 0xF3C875)
    static let fieldFill = adaptive(light: 0xFFFFFF, dark: 0x1C3157)
    /// Darkened from #D9D2BE so field edges reach 3:1 against the surface (WCAG 1.4.11).
    static let fieldBorder = adaptive(light: 0x8F8A7C, dark: 0x7A89AB)
    static let danger = adaptive(light: 0xB3261E, dark: 0xF2B8B5)

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

/// Poppins (OFL), scaled with Dynamic Type: Bold headings, Medium buttons and labels, Regular body.
enum SinagFont {
    static func bold(_ size: CGFloat, relativeTo style: Font.TextStyle) -> Font {
        .custom("Poppins-Bold", size: size, relativeTo: style)
    }

    static func medium(_ size: CGFloat, relativeTo style: Font.TextStyle) -> Font {
        .custom("Poppins-Medium", size: size, relativeTo: style)
    }

    static func regular(_ size: CGFloat, relativeTo style: Font.TextStyle) -> Font {
        .custom("Poppins-Regular", size: size, relativeTo: style)
    }
}

/// Links, kept in one place.
enum SinagLinks {
    static let privacyPolicy = URL(string: "https://sinagtechlabs.com/privacy.html")
    /// Hide the Terms of Use row while this is nil.
    static let termsOfUse: URL? = nil
    /// GPL-3.0 requires offering the source of this fork.
    static let sourceCode = URL(string: "https://github.com/smartparolph-pixel/WLED-iOS")
}

/// Fields and buttons: 50 pt tall at the default text size, 12 pt corners.
enum SinagMetrics {
    static let controlHeight: CGFloat = 50
    static let cornerRadius: CGFloat = 12
    static let screenPadding: CGFloat = 24
    static let maxFormWidth: CGFloat = 480
}

/// The supplied lockup (wordmark + "BY SINAGTECH LABS INC."): color on Paper, reversed on navy.
struct SinagLockup: View {
    @Environment(\.colorScheme) private var colorScheme
    var reversed: Bool?
    var width: CGFloat = 240

    var body: some View {
        let useReversed = reversed ?? (colorScheme == .dark)
        Image(useReversed ? "SinagLockupReversed" : "SinagLockupColor")
            .resizable()
            .scaledToFit()
            .frame(width: width)
            .accessibilityLabel(Text("Sinag by SinagTech Labs Inc."))
    }
}

enum SinagFieldKind {
    case name, email, password, newPassword

    var isSecure: Bool { self == .password || self == .newPassword }

    var contentType: UITextContentType {
        switch self {
        case .name: return .name
        case .email: return .emailAddress
        case .password: return .password
        case .newPassword: return .newPassword
        }
    }

    var keyboard: UIKeyboardType { self == .email ? .emailAddress : .default }
}

/// Text field with a visible placeholder, an accessibility label, a show/hide toggle for passwords and an
/// inline error (icon + text) underneath.
struct SinagTextField: View {
    let label: String
    @Binding var text: String
    let kind: SinagFieldKind
    var error: String?
    var submitLabel: SubmitLabel = .next
    var onSubmit: () -> Void = {}

    @State private var revealed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                field
                    .font(SinagFont.regular(16, relativeTo: .body))
                    .foregroundStyle(SinagColor.text)
                    .textContentType(kind.contentType)
                    .keyboardType(kind.keyboard)
                    .textInputAutocapitalization(kind == .name ? .words : .never)
                    .autocorrectionDisabled(kind != .name)
                    .submitLabel(submitLabel)
                    .onSubmit(onSubmit)
                    .accessibilityLabel(Text(label))
                if kind.isSecure {
                    Button(revealed ? String(localized: "Hide") : String(localized: "Show")) { revealed.toggle() }
                        .font(SinagFont.medium(14, relativeTo: .subheadline))
                        .foregroundStyle(SinagColor.text)
                        .frame(minWidth: 48, minHeight: 48)
                        .accessibilityLabel(Text(revealed ? "Hide password" : "Show password"))
                }
            }
            .padding(.horizontal, 16)
            .frame(minHeight: SinagMetrics.controlHeight)
            .background(SinagColor.fieldFill, in: RoundedRectangle(cornerRadius: SinagMetrics.cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: SinagMetrics.cornerRadius)
                    .stroke(error == nil ? SinagColor.fieldBorder : SinagColor.danger, lineWidth: 1)
            )
            if let error {
                SinagFieldError(message: error)
            }
        }
    }

    @ViewBuilder
    private var field: some View {
        let prompt = Text(label).foregroundColor(SinagColor.muted)
        if kind.isSecure && !revealed {
            SecureField(label, text: $text, prompt: prompt)
        } else {
            TextField(label, text: $text, prompt: prompt)
        }
    }
}

/// Error under a field: icon and text, never color alone.
struct SinagFieldError: View {
    let message: String

    var body: some View {
        Label {
            Text(message)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
        }
        .font(SinagFont.regular(13, relativeTo: .footnote))
        .foregroundStyle(SinagColor.danger)
        .padding(.leading, 4)
        .accessibilityElement(children: .combine)
    }
}

/// Signal Gold with Lantern Navy text; shows a spinner while `loading`.
struct SinagPrimaryButton: View {
    let title: String
    var loading = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Text(title).opacity(loading ? 0 : 1)
                if loading {
                    ProgressView().tint(SinagColor.lanternNavy)
                }
            }
            .font(SinagFont.medium(16, relativeTo: .headline))
            .foregroundStyle(SinagColor.lanternNavy)
            .frame(maxWidth: .infinity, minHeight: SinagMetrics.controlHeight)
            .background(SinagColor.signalGold.opacity(loading ? 0.6 : 1), in: RoundedRectangle(cornerRadius: SinagMetrics.cornerRadius))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(loading)
        .accessibilityLabel(Text(title))
        .accessibilityValue(loading ? Text("Please wait") : Text(""))
    }
}

/// 1.5 pt outline in the text color (Lantern Navy on Paper, Paper on navy).
struct SinagSecondaryButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(SinagFont.medium(16, relativeTo: .headline))
                .foregroundStyle(SinagColor.text)
                .frame(maxWidth: .infinity, minHeight: SinagMetrics.controlHeight)
                .overlay(
                    RoundedRectangle(cornerRadius: SinagMetrics.cornerRadius)
                        .stroke(SinagColor.text, lineWidth: 1.5)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Text link with a 48 pt touch target. Never gold on Paper: uses the text color.
struct SinagTextLink: View {
    let title: String
    var underline = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .underline(underline)
                .font(SinagFont.regular(14, relativeTo: .footnote))
                .foregroundStyle(SinagColor.text)
                .frame(minHeight: 48)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(UIColor(hex: hex))
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
