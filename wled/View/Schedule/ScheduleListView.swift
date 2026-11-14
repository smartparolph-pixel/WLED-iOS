import SwiftUI

/// "Schedule" screen: the device's schedules with on/off toggles, swipe to delete and "+" to add.
struct ScheduleListView: View {
    @StateObject private var viewModel: ScheduleViewModel

    init(device: DeviceWithState) {
        _viewModel = StateObject(wrappedValue: ScheduleViewModel(device: device))
    }

    var body: some View {
        List {
            ScheduleStatusSection(viewModel: viewModel, onRetry: { Task { await viewModel.load() } })
            if viewModel.loading {
                ProgressView().frame(maxWidth: .infinity)
            } else if viewModel.schedules.isEmpty {
                Text("No schedules yet. Tap + to add one.")
                    .foregroundStyle(.secondary)
            } else {
                Section {
                    ForEach(Array(viewModel.schedules.enumerated()), id: \.offset) { index, schedule in
                        row(index, schedule)
                    }
                } footer: {
                    if !viewModel.canAddAny {
                        Text("This device cannot hold more schedules.")
                    }
                }
            }
        }
        .navigationTitle("Schedule")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add Schedule", systemImage: "plus") { viewModel.openNew() }
                    .disabled(viewModel.loading || !viewModel.canAddAny)
            }
        }
        .navigationDestination(isPresented: editorPresented) {
            ScheduleEditView(viewModel: viewModel)
        }
        .task { await viewModel.load() }
    }

    private var editorPresented: Binding<Bool> {
        Binding(
            get: { viewModel.editor != nil },
            set: { if !$0 { viewModel.editor = nil } }
        )
    }

    private func row(_ index: Int, _ schedule: Schedule) -> some View {
        HStack(spacing: 16) {
            HStack(spacing: 16) {
                ScheduleActionBadge(action: viewModel.action(for: schedule))
                VStack(alignment: .leading, spacing: 2) {
                    Text(ScheduleText.time(schedule)).font(.title2)
                    Text(ScheduleDays.summary(schedule.days)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .onTapGesture { viewModel.openEdit(index) }
            Toggle("Enabled", isOn: Binding(
                get: { schedule.enabled },
                set: { enabled in Task { await viewModel.setEnabled(index, enabled) } }
            ))
            .labelsHidden()
            .disabled(viewModel.saving)
        }
        .padding(.vertical, 4)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                Task { await viewModel.delete(index) }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

/// Light bulb with ON / OFF (or the preset's name) underneath.
struct ScheduleActionBadge: View {
    let action: ScheduleViewModel.Action

    var body: some View {
        let isOn = action != .turnOff
        VStack(spacing: 4) {
            Image(systemName: isOn ? "lightbulb.fill" : "lightbulb")
                .font(.title3)
                .frame(width: 40, height: 40)
                .foregroundStyle(isOn ? Color.accentColor : Color.secondary)
                .background(Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: 56)
    }

    private var label: String {
        switch action {
        case .turnOn: return String(localized: "ON")
        case .turnOff: return String(localized: "OFF")
        case .preset(_, let name): return name.isEmpty ? String(localized: "No preset") : name
        }
    }
}

/// Error text, PIN entry and retry, shared by both screens.
struct ScheduleStatusSection: View {
    @ObservedObject var viewModel: ScheduleViewModel
    var onRetry: (() -> Void)?

    var body: some View {
        if viewModel.error != nil || viewModel.needsPin {
            Section {
                if let error = viewModel.error {
                    Text(error).foregroundStyle(.red)
                }
                if viewModel.needsPin {
                    SecureField("Device settings PIN", text: $viewModel.pin)
                        .keyboardType(.numberPad)
                }
                if let onRetry, viewModel.error != nil {
                    Button("Retry", action: onRetry)
                }
            }
        }
    }
}

/// Display texts for a schedule. Times follow the phone's 12/24-hour setting.
enum ScheduleText {
    static func time(_ schedule: Schedule) -> String {
        let offset = abs(schedule.minute)
        switch schedule.trigger {
        case .time:
            if schedule.hour >= 24 {
                return String(localized: "Every hour at :\(String(format: "%02ld", schedule.minute))")
            }
            var components = DateComponents()
            components.hour = schedule.hour
            components.minute = schedule.minute
            let date = Calendar.current.date(from: components) ?? Date()
            return date.formatted(date: .omitted, time: .shortened)
        case .sunrise:
            if schedule.minute < 0 { return String(localized: "\(offset) min before sunrise") }
            if schedule.minute > 0 { return String(localized: "\(offset) min after sunrise") }
            return String(localized: "At sunrise")
        case .sunset:
            if schedule.minute < 0 { return String(localized: "\(offset) min before sunset") }
            if schedule.minute > 0 { return String(localized: "\(offset) min after sunset") }
            return String(localized: "At sunset")
        }
    }
}

#Preview {
    NavigationStack {
        ScheduleListView(device: PreviewData.onlineDevice)
    }
}
