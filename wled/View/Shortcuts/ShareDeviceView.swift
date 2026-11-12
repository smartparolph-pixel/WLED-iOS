import CoreImage.CIFilterBuiltins
import SwiftUI

/// "Share Parol": a QR code another phone on the same WiFi scans to add this lantern. It holds the lantern's
/// address as a `wled://` link: the iPhone Camera opens it in Sinag, and Sinag on Android scans it from its
/// menu. No password or account is involved, since anyone on the home WiFi can already reach the lantern.
struct ShareDeviceView: View {
    @ObservedObject var device: DeviceWithState

    var body: some View {
        let address = device.device.address ?? ""
        ScrollView {
            VStack(spacing: 16) {
                if let image = Self.qrCode(for: ParolShareLink.qrLink(address: address)) {
                    Image(uiImage: image)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 220, height: 220)
                        .padding(12)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
                        .accessibilityLabel("QR code to add \(device.device.displayName) on another phone")
                }
                Text("On the other phone, join the same WiFi and scan this code with the Camera, or choose Scan Parol QR code in Sinag's menu on Android.")
                    .font(.callout)
                    .multilineTextAlignment(.center)
                Text(address)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                ShareLink(item: shareMessage(address: address)) {
                    Label("Share Link", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.borderedProminent)
                if let page = URL(string: ParolShareLink.downloadPage) {
                    Link("Don't have Sinag? Get it free from the App Store or Google Play.", destination: page)
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                }
            }
            .padding()
        }
        .navigationTitle("Share \(device.device.displayName)")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Sent through Messages, WhatsApp and the like: the web link opens Sinag, or the download page.
    private func shareMessage(address: String) -> String {
        let name = device.device.displayName
        let link = ParolShareLink.webLink(address: address)
        return String(localized: "Add my Parol “\(name)” in the Sinag app (on the same WiFi): \(link)")
    }

    private static func qrCode(for text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)),
              let cgImage = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

/// The `wled://` links shared as QR codes, and opening them.
enum ParolShareLink {
    static let scheme = "wled"
    private static let webHosts: Set<String> = ["sinagtechlabs.com", "www.sinagtechlabs.com"]
    private static let webPath = "/smartparol.html"
    /// The Sinag download page, also shown to people without the app who open a share link.
    static let downloadPage = "https://sinagtechlabs.com/smartparol.html"
    /// The QR code uses the web link once the page and apple-app-site-association are live (see the
    /// Android repository's docs/website); until then it uses the wled:// link, which needs Sinag installed.
    static let qrUsesWebLink = false

    static func url(address: String) -> String { "\(scheme)://\(address)" }

    /// Web link to a lantern: opens Sinag when installed (once Associated Domains is set up), the download
    /// page otherwise.
    static func webLink(address: String) -> String {
        var components = URLComponents(string: downloadPage)
        components?.queryItems = [URLQueryItem(name: "a", value: address)]
        return components?.string ?? downloadPage
    }

    static func qrLink(address: String) -> String { qrUsesWebLink ? webLink(address: address) : url(address: address) }

    /// The lantern address in a share link (wled:// or the web link), or nil if `url` is not one.
    static func address(from url: URL) -> String? {
        switch url.scheme?.lowercased() {
        case scheme:
            guard let host = url.host, !host.isEmpty else { return nil }
            return host
        case "https":
            guard let host = url.host?.lowercased(), webHosts.contains(host), url.path == webPath,
                  let address = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                    .queryItems?.first(where: { $0.name == "a" })?.value,
                  address.range(of: "^[A-Za-z0-9.-]{1,253}$", options: .regularExpression) != nil
            else { return nil }
            return address
        default:
            return nil
        }
    }
}
