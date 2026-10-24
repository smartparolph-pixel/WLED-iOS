import SwiftUI

struct ProvisionView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = ProvisionViewModel()
    @State private var showPassword = false

    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 12) {
                switch viewModel.step {
                case .form(let ssidError, let errorMessage):
                    form(ssidError: ssidError, errorMessage: errorMessage)
                case .working(let progress):
                    working(progress)
                case .success(let deviceName):
                    success(deviceName)
                }
                Spacer()
            }
            .padding()
            .animation(.easeInOut, value: viewModel.step)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") {
                        viewModel.cancel()
                        dismiss()
                    }
                }
                if viewModel.step.isForm {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Start", systemImage: "checkmark") { viewModel.start() }
                    }
                }
            }
            .navigationTitle("Set Up New Device")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
        .interactiveDismissDisabled(!viewModel.step.isForm)
    }

    @ViewBuilder
    private func form(ssidError: String, errorMessage: String) -> some View {
        Text("Power on your device, then enter the WiFi network it should join. Your phone will ask permission to connect to the device's setup network.")
            .font(.callout)
        if !errorMessage.isEmpty {
            Text(errorMessage).foregroundStyle(.red).font(.callout)
        }
        TextField("Home WiFi name", text: $viewModel.homeSsid)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .textFieldStyle(.roundedBorder)
        if !ssidError.isEmpty {
            Text(ssidError).foregroundStyle(.red).font(.caption.bold())
        }
        Group {
            if showPassword {
                TextField("Home WiFi password", text: $viewModel.homePassword)
            } else {
                SecureField("Home WiFi password", text: $viewModel.homePassword)
            }
        }
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .textFieldStyle(.roundedBorder)
        .submitLabel(.go)
        .onSubmit { viewModel.start() }
        Toggle("Show password", isOn: $showPassword)
    }

    private func working(_ progress: ProvisioningProgress) -> some View {
        VStack(spacing: 12) {
            ProgressView().controlSize(.large).padding()
            Text(label(for: progress))
        }
        .frame(maxWidth: .infinity)
    }

    private func success(_ name: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.seal")
                .font(.system(size: 50))
                .foregroundStyle(.green)
                .padding()
            Text("\(name) was added")
            Button("Done") { dismiss() }.buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
    }

    private func label(for progress: ProvisioningProgress) -> LocalizedStringKey {
        switch progress {
        case .joiningSetupNetwork: return "Connecting to the device…"
        case .sendingCredentials: return "Sending WiFi details…"
        case .rebootingDevice: return "Restarting the device…"
        case .waitingForDevice: return "Looking for the device on your WiFi…"
        }
    }
}

#Preview {
    ProvisionView()
}
