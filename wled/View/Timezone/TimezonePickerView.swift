import SwiftUI

@MainActor
final class TimezonePickerViewModel: ObservableObject {

    enum ApplyState: Equatable {
        case idle
        case applying
        case applied(WledTimezoneSetting)
        case failed(String)
    }

    @Published var query = ""
    @Published var selectedId = TimeZone.current.identifier
    @Published var pin = ""
    @Published private(set) var needsPin = false
    @Published private(set) var applyState: ApplyState = .idle
    @Published private(set) var options: [TimezoneOption] = []

    private let address: String?

    init(address: String?) {
        self.address = address
    }

    var visibleOptions: [TimezoneOption] { TimezoneCatalog.filter(options, query: query) }
    var selected: TimezoneOption? { options.first { $0.id == selectedId } }

    func load() {
        if options.isEmpty { options = TimezoneCatalog.options() }
    }

    func select(_ id: String) {
        selectedId = id
        applyState = .idle
    }

    /// Sends the closest WLED zone for the selection with a partial `POST /json/cfg`.
    func apply() async {
        let unreachable = String(localized: "Could not reach the device. Make sure it is on and connected.")
        guard let address, let url = URL(string: "http://\(address)/json/cfg") else {
            applyState = .failed(unreachable)
            return
        }
        let setting = TimezoneCatalog.setting(for: selectedId)
        applyState = .applying
        do {
            var request = URLRequest(url: url, timeoutInterval: 10)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try TimezonePayloads.configJSON(setting, pin: pin)
            let (_, response) = try await URLSession.shared.data(for: request)
            switch (response as? HTTPURLResponse)?.statusCode ?? 0 {
            case 200..<300:
                applyState = .applied(setting)
            case 401:
                needsPin = true
                applyState = .failed(String(localized: "This device is protected by a settings PIN. Enter it and try again."))
            default:
                applyState = .failed(String(localized: "The device did not accept the time zone."))
            }
        } catch {
            applyState = .failed(unreachable)
        }
    }
}

/// Lets the user pick any IANA timezone for a device. WLED only understands 25 built-in zones, so the
/// choice is mapped onto the closest one (plus a fixed offset) before it is sent.
struct TimezonePickerView: View {
    @StateObject private var viewModel: TimezonePickerViewModel

    init(device: Device) {
        _viewModel = StateObject(wrappedValue: TimezonePickerViewModel(address: device.address))
    }

    var body: some View {
        List {
            Section {
                if let selected = viewModel.selected {
                    Text("Selected: \(selected.offsetLabel) \(selected.city)")
                }
                if viewModel.needsPin {
                    SecureField("Device settings PIN", text: $viewModel.pin)
                        .keyboardType(.numberPad)
                }
                status
            }
            Section {
                ForEach(viewModel.visibleOptions) { option in
                    row(option)
                }
            }
        }
        .searchable(text: $viewModel.query, prompt: "Search city, country or UTC offset")
        .navigationTitle("Device Time Zone")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Apply") {
                    Task { await viewModel.apply() }
                }
                .disabled(viewModel.selected == nil || viewModel.applyState == .applying)
            }
        }
        .task { viewModel.load() }
    }

    private func row(_ option: TimezoneOption) -> some View {
        Button {
            viewModel.select(option.id)
        } label: {
            HStack {
                VStack(alignment: .leading) {
                    Text(verbatim: "\(option.offsetLabel)  \(option.city)")
                    Text(verbatim: "\(option.region) · \(option.displayName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if option.id == viewModel.selectedId {
                    Image(systemName: "checkmark").foregroundStyle(.tint)
                }
            }
        }
        .foregroundStyle(.primary)
    }

    @ViewBuilder
    private var status: some View {
        switch viewModel.applyState {
        case .idle:
            EmptyView()
        case .applying:
            ProgressView()
        case .applied(let setting):
            let zone = WledTimezones.all.first { $0.index == setting.index }?.label ?? ""
            Text("Saved. The device now uses \(zone) and gets its time from the internet.")
            if !setting.exact {
                Text("This device's firmware does not know the daylight saving rules of this zone. The time is correct now, but will not change automatically for daylight saving.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        case .failed(let message):
            Text(message).foregroundStyle(.red)
        }
    }
}

#Preview {
    NavigationStack {
        TimezonePickerView(device: PreviewData.onlineDevice.device)
    }
}
