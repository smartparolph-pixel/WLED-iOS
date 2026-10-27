import SwiftUI

/// About (Settings → About): version, Privacy Policy, Terms of Use (hidden until a URL exists), credits.
struct AboutView: View {
    @Environment(\.openURL) private var openURL
    var version: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                AboutRow(title: String(localized: "Version"), value: version)
                if let url = SinagLinks.privacyPolicy {
                    AboutRow(title: String(localized: "Privacy Policy"), emphasized: true) { openURL(url) }
                }
                if let url = SinagLinks.termsOfUse {
                    AboutRow(title: String(localized: "Terms of Use")) { openURL(url) }
                }
                footer.padding(.top, 48)
            }
            .frame(maxWidth: SinagMetrics.maxFormWidth)
            .padding(SinagMetrics.screenPadding)
            .frame(maxWidth: .infinity)
        }
        .background(SinagColor.background.ignoresSafeArea())
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var footer: some View {
        VStack(spacing: 4) {
            Text("Sinag by SinagTech Labs Inc.")
            Text("Powered by WLED")
            // GPL-3.0 "Appropriate Legal Notices": license, no warranty, and where to get the source.
            if let url = SinagLinks.sourceCode {
                Button {
                    openURL(url)
                } label: {
                    Text("Based on WLED Native. Free software under GPL-3.0, with no warranty. View source code")
                        .underline()
                        .foregroundStyle(SinagColor.text)
                        .frame(minHeight: 48)
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
            }
        }
        .font(SinagFont.regular(13, relativeTo: .footnote))
        .foregroundStyle(SinagColor.muted)
        .multilineTextAlignment(.center)
    }
}

private struct AboutRow: View {
    let title: String
    var value: String?
    var emphasized = false
    var action: (() -> Void)?

    var body: some View {
        if let action {
            Button(action: action) { content(showChevron: true) }
                .buttonStyle(.plain)
                .accessibilityAddTraits(.isLink)
        } else {
            content(showChevron: false)
                .accessibilityElement(children: .combine)
        }
    }

    private func content(showChevron: Bool) -> some View {
        HStack {
            Text(title)
                .font(emphasized ? SinagFont.medium(16, relativeTo: .headline) : SinagFont.regular(16, relativeTo: .body))
                .foregroundStyle(SinagColor.text)
            Spacer()
            if let value {
                Text(value)
                    .font(SinagFont.regular(16, relativeTo: .body))
                    .foregroundStyle(SinagColor.muted)
            }
            if showChevron {
                Image(systemName: "chevron.right").foregroundStyle(SinagColor.muted).accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: SinagMetrics.controlHeight)
        .background(SinagColor.fieldFill, in: RoundedRectangle(cornerRadius: SinagMetrics.cornerRadius))
        .overlay(RoundedRectangle(cornerRadius: SinagMetrics.cornerRadius).stroke(SinagColor.fieldBorder, lineWidth: 1))
        .contentShape(Rectangle())
    }
}

/// The app session, readable from sheets such as Settings (nil in previews).
private struct AppSessionKey: EnvironmentKey {
    static let defaultValue: AppSession? = nil
}

extension EnvironmentValues {
    var appSession: AppSession? {
        get { self[AppSessionKey.self] }
        set { self[AppSessionKey.self] = newValue }
    }
}

#Preview("About - light") {
    NavigationStack { AboutView(version: "1.0") }.preferredColorScheme(.light)
}

#Preview("About - dark") {
    NavigationStack { AboutView(version: "1.0") }.preferredColorScheme(.dark)
}
