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
                if let image = Self.qrCode(for: ParolShareLink.url(address: address)) {
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
            }
            .padding()
        }
        .navigationTitle("Share \(device.device.displayName)")
        .navigationBarTitleDisplayMode(.inline)
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

    static func url(address: String) -> String { "\(scheme)://\(address)" }

    /// The lantern address in a share link, or nil if `url` is not one.
    static func address(from url: URL) -> String? {
        guard url.scheme?.lowercased() == scheme, let host = url.host, !host.isEmpty else { return nil }
        return host
    }
}
