import SwiftUI

/// "New Schedule" / "Edit Schedule": time or sunrise/sunset, turn on/off, repeat days, delete.
struct ScheduleEditView: View {
    @ObservedObject var viewModel: ScheduleViewModel
    @State private var locationFailed = false
    @State private var phoneLocation: PhoneLocation?

    var body: some View {
        if let editor = viewModel.editor {
            form(editor)
                .navigationTitle(editor.index == nil ? "New Schedule" : "Edit Schedule")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            Task { _ = await viewModel.saveEditor() }
                        }
                        .disabled(editor.draft.days & Schedule.allDays == 0 || viewModel.saving)
                    }
                }
        }
    }

    private func form(_ editor: ScheduleViewModel.Editor) -> some View {
        Form {
            ScheduleStatusSection(viewModel: viewModel)
            Section("At") {
                atSection(editor)
            }
            Section("Turn Device") {
                actionRow(.turnOn, String(localized: "On"), editor)
                actionRow(.turnOff, String(localized: "Off"), editor)
                if case .preset(_, let name) = editor.action {
                    actionRow(
                        editor.action,
                        String(localized: "Preset: \(name.isEmpty ? String(localized: "No preset") : name)"),
                        editor
                    )
                }
            }
            Section {
                dayCircles(editor.draft.days)
            } header: {
                Text("Repeat")
            } footer: {
                let summary = ScheduleDays.summary(editor.draft.days)
                Text(summary.isEmpty ? String(localized: "Select at least one day") : summary)
                    .font(.body)
                    .foregroundStyle(summary.isEmpty ? Color.red : Color.secondary)
            }
            if editor.index != nil {
                Section {
                    Button(role: .destructive) {
                        Task { await viewModel.deleteEditing() }
                    } label: {
                        Text("Delete Schedule").frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    // MARK: - At

    @ViewBuilder
    private func atSection(_ editor: ScheduleViewModel.Editor) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(triggerLabel(editor.draft.trigger)).foregroundStyle(.secondary)
            Text(ScheduleText.time(editor.draft)).font(.title)
        }
        Picker("At", selection: triggerBinding) {
            ForEach(ScheduleTrigger.allCases.filter { viewModel.canUse($0) }, id: \.self) { trigger in
                Text(triggerLabel(trigger)).tag(trigger)
            }
        }
        .pickerStyle(.segmented)
        .listRowSeparator(.hidden)
        if editor.draft.trigger == .time {
            DatePicker("Time", selection: timeBinding, displayedComponents: .hourAndMinute)
                .datePickerStyle(.wheel)
                .labelsHidden()
                .frame(maxWidth: .infinity)
        } else {
            Stepper(
                ScheduleText.time(editor.draft),
                value: offsetBinding,
                in: -viewModel.limits.maxOffsetMinutes...viewModel.limits.maxOffsetMinutes,
                step: 5
            )
            locationRow(editor)
        }
    }

    @ViewBuilder
    private func locationRow(_ editor: ScheduleViewModel.Editor) -> some View {
        if editor.pendingLatitude != nil {
            Text("Your phone's location will be saved to the device.")
                .font(.callout)
                .foregroundStyle(.secondary)
        } else if !viewModel.hasLocation || locationFailed {
            Text(locationFailed ? "Could not get your location." : "Sunrise and sunset need the device's location.")
                .font(.callout)
                .foregroundStyle(.red)
            Button("Use phone location", systemImage: "location") {
                Task {
                    let locator = PhoneLocation()
                    phoneLocation = locator
                    if let coordinate = await locator.request() {
                        viewModel.setLocation(latitude: coordinate.0, longitude: coordinate.1)
                        locationFailed = false
                    } else {
                        locationFailed = true
                    }
                    phoneLocation = nil
                }
            }
        }
    }

    private func triggerLabel(_ trigger: ScheduleTrigger) -> String {
        switch trigger {
        case .time: return String(localized: "Custom Time")
        case .sunrise: return String(localized: "Sunrise")
        case .sunset: return String(localized: "Sunset")
        }
    }

    // MARK: - Turn Device

    private func actionRow(_ action: ScheduleViewModel.Action, _ label: String, _ editor: ScheduleViewModel.Editor) -> some View {
        Button {
            viewModel.editor?.action = action
        } label: {
            HStack {
                Text(label).foregroundStyle(.primary)
                Spacer()
                if editor.action == action {
                    Image(systemName: "checkmark").foregroundStyle(.tint)
                }
            }
        }
    }

    // MARK: - Repeat

    private func dayCircles(_ days: Int) -> some View {
        HStack {
            ForEach(ScheduleDays.displayOrder, id: \.self) { bit in
                let selected = ScheduleDays.isSelected(days, bit)
                Button {
                    viewModel.editor?.draft.days = ScheduleDays.toggle(days, bit)
                } label: {
                    Text(ScheduleDays.letter(bit))
                        .font(.headline)
                        .frame(width: 40, height: 40)
                        .foregroundStyle(selected ? Color.white : Color.secondary)
                        .background(Circle().fill(selected ? Color.accentColor : Color.clear))
                        .overlay(Circle().stroke(Color.secondary, lineWidth: selected ? 0 : 2))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(ScheduleDays.name(bit))
                .accessibilityAddTraits(selected ? .isSelected : [])
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: - Bindings

    private var triggerBinding: Binding<ScheduleTrigger> {
        Binding(
            get: { viewModel.editor?.draft.trigger ?? .time },
            set: { trigger in
                guard var draft = viewModel.editor?.draft, draft.trigger != trigger else { return }
                draft.trigger = trigger
                draft.minute = 0
                viewModel.editor?.draft = draft
            }
        )
    }

    private var timeBinding: Binding<Date> {
        Binding(
            get: {
                let draft = viewModel.editor?.draft
                var components = DateComponents()
                components.hour = min(draft?.hour ?? 0, 23)
                components.minute = draft?.minute ?? 0
                return Calendar.current.date(from: components) ?? Date()
            },
            set: { date in
                let components = Calendar.current.dateComponents([.hour, .minute], from: date)
                viewModel.editor?.draft.hour = components.hour ?? 0
                viewModel.editor?.draft.minute = components.minute ?? 0
            }
        )
    }

    private var offsetBinding: Binding<Int> {
        Binding(
            get: { viewModel.editor?.draft.minute ?? 0 },
            set: { viewModel.editor?.draft.minute = $0 }
        )
    }
}
