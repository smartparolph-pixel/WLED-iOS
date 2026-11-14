//
//  Settings.swift
//  WLED
//
//  Created by Christophe Gagnier on 2025-12-28.
//

import SwiftUI

struct Settings: View {
    @Binding var showHiddenDevices: Bool
    @Binding var showOfflineDevices: Bool

    @ObservedObject private var appLock = AppLock.shared

    // Environment to dismiss the sheet
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("View Options") {
                    Toggle(isOn: $showHiddenDevices) {
                        Label("Show Hidden Devices", systemImage: "eye")
                    }

                    Toggle(isOn: $showOfflineDevices) {
                        Label("Show Offline Devices", systemImage: "wifi.slash")
                    }
                }

                appLockSection

                Section {
                    if let url = URL(string: "https://kno.wled.ge/") {
                        Link(destination: url) {
                            Label("WLED Documentation", systemImage: "questionmark.circle")
                        }
                    }
                } header: {
                    Text("About")
                } footer: {
                    VStack(alignment: .center) {
                        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
                        let bundleVersion = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1.0"

                        Text("Made by Moustachauve")
                        Text("Version \(version) (\(bundleVersion))")
                    }
                    .frame(maxWidth: .infinity)
                }

            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    /// Every change needs Face ID, Touch ID or the passcode, so nobody else can change it.
    private var appLockSection: some View {
        let available = AppLock.isAvailable
        return Section {
            Picker("App Lock", selection: Binding(
                get: { appLock.mode },
                set: { mode in
                    Task {
                        if await appLock.authenticate(reason: String(localized: "Confirm it's you to change App Lock")) {
                            appLock.mode = mode
                        }
                    }
                }
            )) {
                Text("Off").tag(AppLockMode.off)
                Text("Settings Only").tag(AppLockMode.settingsOnly)
                Text("Whole App").tag(AppLockMode.wholeApp)
            }
            .disabled(!available && appLock.mode == .off)
            if appLock.mode != .off {
                Picker("Ask Again After", selection: $appLock.timeout) {
                    Text("Immediately").tag(AppLockTimeout.immediately)
                    Text("2 Minutes").tag(AppLockTimeout.twoMinutes)
                    Text("5 Minutes").tag(AppLockTimeout.fiveMinutes)
                }
            }
        } header: {
            Text("App Lock")
        } footer: {
            if !available {
                Text("Set a passcode on this iPhone to use App Lock.")
            } else if appLock.mode == .settingsOnly {
                Text("Lights stay free to use. Opening settings, setting up or editing lanterns, schedules and playlist edits need Face ID, Touch ID or the passcode.")
            } else {
                Text("Uses this iPhone's Face ID, Touch ID or passcode. Nothing is stored by Sinag.")
            }
        }
    }
}

#Preview {
    Settings(
        showHiddenDevices: .constant(true), showOfflineDevices: .constant(true)
    )
}
