import SwiftUI

/// Bottom bar on the main page with shortcuts to Schedule, Presets & Playlists and Time Zone. With one
/// device the feature opens for it straight away; with several, a list asks which device first.
struct DeviceShortcutBar: View {
    let devices: [DeviceWithState]

    enum Shortcut: String, CaseIterable, Identifiable {
        case schedule, presets, timeZone

        var id: Self { self }

        var title: LocalizedStringKey {
            switch self {
            case .schedule: return "Schedule"
            case .presets: return "Presets & Playlists"
            case .timeZone: return "Time Zone"
            }
        }

        var systemImage: String {
            switch self {
            case .schedule: return "calendar"
            case .presets: return "sparkles"
            case .timeZone: return "globe"
            }
        }
    }

    private struct Opened: Identifiable {
        let shortcut: Shortcut
        let device: DeviceWithState
        var id: String { "\(shortcut.rawValue)-\(device.id)" }
    }

    @State private var choosingFor: Shortcut?
    @State private var opened: Opened?

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Shortcut.allCases) { shortcut in
                Button {
                    tap(shortcut)
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: shortcut.systemImage)
                            .font(.system(size: 20))
                            .accessibilityHidden(true)
                        Text(shortcut.title)
                            .font(.caption2)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(devices.isEmpty ? Color.secondary : Color.accentColor)
                .disabled(devices.isEmpty)
            }
        }
        .padding(.vertical, 6)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
        .confirmationDialog(
            "Choose a device",
            isPresented: Binding(get: { choosingFor != nil }, set: { if !$0 { choosingFor = nil } }),
            titleVisibility: .visible,
            presenting: choosingFor
        ) { shortcut in
            ForEach(devices) { device in
                Button(device.device.displayName) {
                    opened = Opened(shortcut: shortcut, device: device)
                }
            }
        }
        .sheet(item: $opened) { opened in
            NavigationStack {
                destination(opened)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { self.opened = nil }
                        }
                    }
            }
        }
    }

    @ViewBuilder
    private func destination(_ opened: Opened) -> some View {
        switch opened.shortcut {
        case .schedule: ScheduleListView(device: opened.device)
        case .presets: PresetPacksView(device: opened.device.device)
        case .timeZone: TimezonePickerView(device: opened.device.device)
        }
    }

    private func tap(_ shortcut: Shortcut) {
        if devices.count == 1, let device = devices.first {
            opened = Opened(shortcut: shortcut, device: device)
        } else {
            choosingFor = shortcut
        }
    }
}
