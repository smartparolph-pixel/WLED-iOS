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

    // Environment to dismiss the sheet
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appSession) private var appSession

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

                Section {
                    NavigationLink {
                        AboutView()
                    } label: {
                        Label("About Sinag", systemImage: "info.circle")
                    }
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

                if let appSession {
                    Section {
                        Button(role: .destructive) {
                            dismiss()
                            Task { await appSession.signOut() }
                        } label: {
                            Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                    }
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
}

#Preview {
    Settings(
        showHiddenDevices: .constant(true), showOfflineDevices: .constant(true)
    )
}
