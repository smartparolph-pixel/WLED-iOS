import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// The lantern's own WiFi name and password, with Show and Copy.
struct LanternWifiCard: View {
    let credentials: LanternWifiCredentials
    @State private var showPassword = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Parol WiFi").font(.headline)
            Text("Name: \(credentials.ssid)")
            Text("Password: \(showPassword ? credentials.password : "••••••••")")
                .font(.body.monospaced())
            HStack {
                Button(showPassword ? "Hide Password" : "Show Password") { showPassword.toggle() }
                Spacer()
                Button("Copy Password") { copy() }
            }
            .buttonStyle(.borderless)
            Text("Your Parol opens this WiFi when it can't reach your home WiFi, for example after you move it. Sinag uses it for Direct connection; you only need the password to join from another phone.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    /// Kept on this device only (not Handoff's Universal Clipboard) and cleared after 2 minutes.
    private func copy() {
        UIPasteboard.general.setItems(
            [[UTType.plainText.identifier: credentials.password]],
            options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(120)]
        )
    }
}

@MainActor
final class LanternWifiViewModel: ObservableObject {
    @Published private(set) var loading = true
    @Published private(set) var lanternSsid: String?
    @Published private(set) var status: LanternWifiStatus = .unknown
    @Published private(set) var saved: LanternWifiCredentials?
    @Published private(set) var saving = false
    @Published private(set) var needsPin = false
    @Published private(set) var changed = false
    @Published var pin = ""
    @Published var error: String?

    private let address: String?
    private let mac: String?
    private let store = LanternWifiStore.shared
    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        return URLSession(configuration: configuration)
    }()

    init(address: String?, mac: String?) {
        self.address = address
        self.mac = mac
    }

    func load() async {
        loading = true
        error = nil
        saved = mac.flatMap { store.credentials(forMac: $0) }
        var reported: (ssid: String?, passwordLength: Int?) = (nil, nil)
        if let url = url("/json/cfg"),
           let result = try? await session.data(from: url),
           (result.1 as? HTTPURLResponse)?.statusCode == 200,
           let cfg = try? JSONSerialization.jsonObject(with: result.0) as? [String: Any] {
            reported = LanternWifi.fromConfig(cfg)
        }
        lanternSsid = reported.ssid
        status = LanternWifi.status(ssid: reported.ssid, passwordLength: reported.passwordLength, saved: saved)
        if reported.ssid == nil {
            error = String(localized: "Couldn't reach the Parol. Check that it's online and try again.")
        }
        loading = false
    }

    /// Gives the lantern its own name and a new random password (or the one saved for it), then saves it.
    func secure() async {
        guard !saving, let mac, let url = url("/json/cfg") else { return }
        let credentials = status == .shared ? (saved ?? LanternWifi.newCredentials(mac: mac))
            : LanternWifi.newCredentials(mac: mac)
        saving = true
        error = nil
        defer { saving = false }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? LanternWifi.configJSON(credentials, pin: pin.isEmpty ? nil : pin)
        guard let result = try? await session.data(for: request),
              let code = (result.1 as? HTTPURLResponse)?.statusCode else {
            error = String(localized: "Couldn't reach the Parol. Check that it's online and try again.")
            return
        }
        switch code {
        case 200..<300:
            store.save(credentials, forMac: mac)
            saved = credentials
            lanternSsid = credentials.ssid
            status = .secured
            changed = true
            needsPin = false
        case 401:
            needsPin = true
            error = String(localized: "This Parol has a settings PIN. Enter it and try again.")
        default:
            error = String(localized: "The Parol didn't accept the change. Try again.")
        }
    }

    private func url(_ path: String) -> URL? {
        guard let address, !address.isEmpty else { return nil }
        return URL(string: "http://\(address)\(path)")
    }
}

/// "Parol WiFi" in the lantern's settings: shows its own WiFi and gives it its own name and password.
struct LanternWifiView: View {
    @StateObject private var viewModel: LanternWifiViewModel

    init(address: String?, mac: String?) {
        _viewModel = StateObject(wrappedValue: LanternWifiViewModel(address: address, mac: mac))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if viewModel.loading {
                    ProgressView().frame(maxWidth: .infinity).padding()
                } else {
                    content
                }
            }
            .padding()
        }
        .navigationTitle("Parol WiFi")
        .task { await viewModel.load() }
    }

    @ViewBuilder
    private var content: some View {
        let ssid = viewModel.lanternSsid ?? ""
        switch viewModel.status {
        case .shared:
            Text("This Parol still uses the shared WiFi \(ssid) with the password wled1234, which anyone nearby can join. Give it its own name and password.")
        case .notOnThisPhone:
            Text("This Parol has its own WiFi (\(ssid)), but its password isn't saved on this phone. Set a new password to use Direct connection from this phone.")
        case .secured:
            if viewModel.changed {
                Text("Done. The Parol uses its new WiFi the next time it opens it.")
            }
            if let saved = viewModel.saved {
                LanternWifiCard(credentials: saved)
            }
        case .unknown:
            EmptyView()
        }
        if viewModel.needsPin {
            SecureField("Settings PIN", text: $viewModel.pin)
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
        }
        if let error = viewModel.error {
            Text(error).foregroundStyle(.red).font(.callout)
        }
        if viewModel.status != .unknown {
            Button(viewModel.status == .shared ? "Secure Parol WiFi" : "New Password") {
                Task { await viewModel.secure() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.saving)
        } else {
            Button("Try Again") { Task { await viewModel.load() } }
        }
    }
}
