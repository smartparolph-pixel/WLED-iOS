import CoreLocation
import Foundation

/// Reads and writes the device's own schedule list (the one under Config → Time & Macros) through
/// `/json/cfg`, so both places always show the same schedules.
@MainActor
final class ScheduleViewModel: ObservableObject {

    /// What a schedule does when it fires.
    enum Action: Equatable {
        case turnOn
        case turnOff
        /// A preset picked under Config → Time & Macros, kept as is.
        case preset(id: Int, name: String)
    }

    struct Editor: Equatable {
        /// Index in the list, or nil for a new schedule.
        var index: Int?
        var draft: Schedule
        var action: Action
        var pendingLatitude: Double?
        var pendingLongitude: Double?
    }

    @Published private(set) var loading = true
    @Published private(set) var saving = false
    @Published private(set) var error: String?
    @Published private(set) var schedules: [Schedule] = []
    @Published private(set) var presets: [Int: String] = [:]
    @Published private(set) var limits = ScheduleLimits.legacy
    @Published private(set) var hasLocation = true
    @Published private(set) var needsPin = false
    @Published var pin = ""
    @Published var editor: Editor?

    private let address: String?
    private let currentFormat: Bool
    private var ntpEnabled = true

    init(device: DeviceWithState) {
        address = device.device.address
        let info = device.stateInfo?.info
        currentFormat = ScheduleCodec.isCurrentFormat(buildId: info?.buildId)
        if currentFormat {
            limits = .current(isEsp8266: (info?.platformName ?? "").contains("8266"))
        }
    }

    var canAddAny: Bool {
        ScheduleTrigger.allCases.contains { limits.canAdd(schedules, $0) }
    }

    func action(for schedule: Schedule) -> Action {
        switch presets[schedule.presetId] {
        case SchedulePresets.onName: return .turnOn
        case SchedulePresets.offName: return .turnOff
        default: return .preset(id: schedule.presetId, name: presets[schedule.presetId] ?? "")
        }
    }

    // MARK: - List

    func load() async {
        loading = true
        error = nil
        defer { loading = false }
        do {
            let (cfgData, cfgResponse) = try await get("/json/cfg")
            if (cfgResponse as? HTTPURLResponse)?.statusCode == 401 {
                needsPin = true
                error = String(localized: "This device is protected by a settings PIN. Enter it and try again.")
                return
            }
            let (presetData, _) = try await get("/presets.json")
            let cfg = (try? JSONSerialization.jsonObject(with: cfgData)) as? [String: Any] ?? [:]
            let presetJSON = (try? JSONSerialization.jsonObject(with: presetData)) as? [String: Any] ?? [:]
            let ntp = (cfg["if"] as? [String: Any])?["ntp"] as? [String: Any]
            let ins = (cfg["timers"] as? [String: Any])?["ins"] as? [Any] ?? []
            schedules = ScheduleCodec.decode(ins, currentFormat: currentFormat)
            presets = SchedulePresets.names(presetJSON)
            ntpEnabled = (ntp?["en"] as? Bool) ?? false
            let latitude = (ntp?["lt"] as? NSNumber)?.doubleValue ?? 0
            let longitude = (ntp?["ln"] as? NSNumber)?.doubleValue ?? 0
            hasLocation = latitude != 0 || longitude != 0
        } catch {
            self.error = unreachableMessage
        }
    }

    func setEnabled(_ index: Int, _ enabled: Bool) async {
        var updated = schedules
        updated[index].enabled = enabled
        await write(updated)
    }

    func delete(_ index: Int) async {
        var updated = schedules
        updated.remove(at: index)
        await write(updated)
    }

    // MARK: - Editor

    func openNew() {
        guard let trigger = ScheduleTrigger.allCases.first(where: { limits.canAdd(schedules, $0) }) else { return }
        let now = Calendar.current.dateComponents([.hour, .minute], from: Date())
        let draft = Schedule(
            trigger: trigger,
            hour: now.hour ?? 0,
            minute: trigger == .time ? (now.minute ?? 0) : 0,
            presetId: 0,
            days: Schedule.allDays,
            enabled: true
        )
        editor = Editor(index: nil, draft: draft, action: .turnOn)
    }

    func openEdit(_ index: Int) {
        let schedule = schedules[index]
        editor = Editor(index: index, draft: schedule, action: action(for: schedule))
    }

    /// True when `trigger` can be chosen for the open editor without exceeding the device's slots.
    func canUse(_ trigger: ScheduleTrigger) -> Bool {
        guard let editor else { return false }
        if editor.draft.trigger == trigger { return true }
        let others = schedules.enumerated().filter { $0.offset != editor.index }.map(\.element)
        return limits.canAdd(others, trigger)
    }

    func setLocation(latitude: Double, longitude: Double) {
        editor?.pendingLatitude = latitude
        editor?.pendingLongitude = longitude
        hasLocation = true
    }

    /// - Returns: True when the schedule was saved and the editor can close.
    func saveEditor() async -> Bool {
        guard let editor, editor.draft.days & Schedule.allDays != 0 else { return false }
        saving = true
        guard let presetId = await presetId(for: editor.action) else {
            saving = false
            if error == nil { error = unreachableMessage }
            return false
        }
        var updated = schedules
        var schedule = editor.draft
        schedule.presetId = presetId
        if let index = editor.index {
            updated[index] = schedule
        } else {
            updated.append(schedule)
        }
        var location: (Double, Double)?
        if let lat = editor.pendingLatitude, let lon = editor.pendingLongitude { location = (lat, lon) }
        let saved = await write(updated, location: location)
        if saved { self.editor = nil }
        return saved
    }

    func deleteEditing() async {
        guard let index = editor?.index else { return }
        editor = nil
        await delete(index)
    }

    // MARK: - Device calls

    private var unreachableMessage: String {
        String(localized: "Could not reach the device. Make sure it is on and connected.")
    }

    private func url(_ path: String) -> URL? {
        guard let address else { return nil }
        return URL(string: "http://\(address)\(path)")
    }

    private func get(_ path: String) async throws -> (Data, URLResponse) {
        guard let url = url(path) else { throw URLError(.badURL) }
        return try await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 10))
    }

    private func post(_ path: String, body: Data) async throws -> Int {
        guard let url = url(path) else { throw URLError(.badURL) }
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        let (_, response) = try await URLSession.shared.data(for: request)
        return (response as? HTTPURLResponse)?.statusCode ?? 0
    }

    /// Finds or creates the preset the schedule should apply.
    private func presetId(for action: Action) async -> Int? {
        switch action {
        case .preset(let id, _): return id
        case .turnOn: return await ensurePreset(SchedulePresets.onName, on: true)
        case .turnOff: return await ensurePreset(SchedulePresets.offName, on: false)
        }
    }

    private func ensurePreset(_ name: String, on: Bool) async -> Int? {
        if let existing = SchedulePresets.find(presets, name: name) { return existing }
        guard let slot = SchedulePresets.freeSlot(presets) else {
            error = String(localized: "The device has no free preset slot for the on/off action.")
            return nil
        }
        guard let body = try? SchedulePresets.saveJSON(id: slot, name: name, on: on),
              let status = try? await post("/json/state", body: body), (200..<300).contains(status) else {
            return nil
        }
        presets[slot] = name
        return slot
    }

    /// Writes the full list; also turns on internet time (with the phone's zone) if it is off.
    @discardableResult
    private func write(_ updated: [Schedule], location: (Double, Double)? = nil) async -> Bool {
        saving = true
        error = nil
        defer { saving = false }
        var ntp: [String: Any] = [:]
        if !ntpEnabled {
            ntp = TimezonePayloads.ntpConfig(TimezoneCatalog.setting(for: TimeZone.current.identifier))
        }
        if let location {
            ntp["lt"] = location.0
            ntp["ln"] = location.1
        }
        do {
            let timers = ScheduleCodec.encode(updated, currentFormat: currentFormat)
            let body = try SchedulePayloads.configJSON(timers: timers, ntp: ntp, pin: pin)
            switch try await post("/json/cfg", body: body) {
            case 200..<300:
                schedules = updated
                ntpEnabled = true
                return true
            case 401:
                needsPin = true
                error = String(localized: "This device is protected by a settings PIN. Enter it and try again.")
            default:
                error = String(localized: "The device did not accept the schedules.")
            }
        } catch {
            self.error = unreachableMessage
        }
        return false
    }
}

/// Asks for "when in use" location once and returns the phone's position.
@MainActor
final class PhoneLocation: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<(Double, Double)?, Never>?

    func request() async -> (Double, Double)? {
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            switch manager.authorizationStatus {
            case .notDetermined: manager.requestWhenInUseAuthorization()
            case .authorizedWhenInUse, .authorizedAlways: manager.requestLocation()
            default: finish(nil)
            }
        }
    }

    private func finish(_ coordinate: (Double, Double)?) {
        continuation?.resume(returning: coordinate)
        continuation = nil
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            switch status {
            case .authorizedWhenInUse, .authorizedAlways: self.manager.requestLocation()
            case .notDetermined: break
            default: self.finish(nil)
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let coordinate = locations.last.map { ($0.coordinate.latitude, $0.coordinate.longitude) }
        Task { @MainActor in self.finish(coordinate) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.finish(nil) }
    }
}
