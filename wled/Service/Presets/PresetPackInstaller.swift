import Foundation

enum PackSetupResult: Equatable, Sendable {
    /// - Parameters:
    ///   - playlistIds: Preset id of each pack's playlist on the device, keyed by playlist name.
    ///   - created: Number of presets and playlists saved now (0 when everything was already there).
    ///   - unavailable: Effects that could not be added (missing in the firmware or no free slot).
    ///   - verified: Everything was found in presets.json afterwards.
    ///   - custom: The user's own playlists (made in the app or on WLED's web page).
    case ready(playlistIds: [String: Int], created: Int, unavailable: [String], verified: Bool, custom: [SavedPlaylist])
    /// None of the packs' effects exist on the device, or it has no free preset slots.
    case nothingAvailable
    /// The device answered but its presets.json is not valid JSON (damaged). Nothing is written then, since
    /// saving into a file that cannot be read can lose every preset in it. `repairPresets()` can rebuild it
    /// from the `kept` entries that are intact, leaving out `dropped` damaged parts. `problem` says where the
    /// file stops being valid, for diagnosis.
    case presetsUnreadable(kept: Int, dropped: Int, problem: String)
    case unreachable

    /// For the editor, which only reads: the Presets & Playlists screen offers the repair.
    static let unreadableMessage = String(
        localized: "The device's presets file could not be read, so nothing was changed. Try again; if it keeps happening, check Presets on the device's web page."
    )

    static func damagedMessage(kept: Int, dropped: Int) -> String {
        String(localized: "This device's presets file is damaged, so nothing was changed. Repair keeps the \(kept) presets and playlists that are intact and removes \(dropped) damaged parts; missing playlists are then added again.")
    }

    /// Effects that could not be added, and a warning if the device did not confirm the saves.
    var notes: String? {
        guard case .ready(_, _, let unavailable, let verified, _) = self else { return nil }
        var parts: [String] = []
        if !unavailable.isEmpty {
            let names = unavailable.joined(separator: ", ")
            parts.append(String(localized: "Not available on this device: \(names)."))
        }
        if !verified {
            parts.append(String(localized: "The device did not confirm every preset; check its Presets list."))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    /// What setting up the playlists did, for the end of Set Up New Device.
    var setupMessage: String {
        switch self {
        case .ready:
            let playing = PresetPacks.playsAfterSetup.playlist.name
            return [String(localized: "Playlists ready. \(playing) is playing now."), notes]
                .compactMap { $0 }
                .joined(separator: " ")
        case .nothingAvailable:
            return String(localized: "Nothing could be added: this device has none of these effects or no free preset slots.")
        case .presetsUnreadable(let kept, let dropped, _):
            return Self.damagedMessage(kept: kept, dropped: dropped)
        case .unreachable:
            return String(localized: "Could not reach the device. Make sure it is on and try again.")
        }
    }
}

/// Last check per device address, valid while its presets.json is unchanged (`info.fs.pmt`).
private actor PresetCheckCache {
    static let shared = PresetCheckCache()
    private var results: [String: (modified: Int64, result: PackSetupResult)] = [:]

    func result(for address: String, modified: Int64?) -> PackSetupResult? {
        guard let modified, let entry = results[address], entry.modified == modified else { return nil }
        return entry.result
    }

    func store(_ result: PackSetupResult, for address: String, modified: Int64) {
        results[address] = (modified, result)
    }

    func forget(_ address: String) {
        results[address] = nil
    }
}

/// Makes sure every `PresetPack` is on a device, without asking: missing presets and playlists are added,
/// those already there (matched by name) are left alone, edits included, so it is safe to run every time.
struct PresetPackInstaller {
    /// Gives the device time to write presets.json after a preset is saved (written right away).
    private static let presetGap: Duration = .milliseconds(500)
    /// Playlists are written in the device's main loop after the reply, so they get longer.
    private static let playlistGap: Duration = .milliseconds(1000)

    let address: String

    /// Saving a preset or playlist also applies it to the lights, so the lights change while anything is
    /// added. Afterwards `play` is started if given, or `PresetPacks.playsAfterSetup` if anything was added,
    /// so the device never ends on a random effect.
    func ensureAll(play: PresetPack? = nil, packs: [PresetPack] = PresetPacks.all) async -> PackSetupResult {
        do {
            let modified = try await presetsModified()
            let cached = await PresetCheckCache.shared.result(for: address, modified: modified)
            let result: PackSetupResult
            if let cached {
                result = cached
            } else {
                result = try await install(packs)
            }
            guard case .ready(let ids, let created, let unavailable, let verified, let custom) = result else {
                return result
            }
            let start = play ?? (cached == nil && created > 0 ? PresetPacks.playsAfterSetup : nil)
            if let start, let id = ids[start.playlist.name] {
                _ = try await post(try PresetPackPayloads.playJSON(id: id))
            }
            if cached == nil, verified, let now = try await presetsModified() {
                let quiet = PackSetupResult.ready(
                    playlistIds: ids, created: 0, unavailable: unavailable, verified: true, custom: custom
                )
                await PresetCheckCache.shared.store(quiet, for: address, modified: now)
            }
            return result
        } catch {
            return .unreachable
        }
    }

    /// Adds what is missing, without starting anything.
    private func install(_ packs: [PresetPack]) async throws -> PackSetupResult {
        let effects = try JSONSerialization.jsonObject(with: try await get("/json/eff")) as? [String] ?? []
        guard !effects.isEmpty else { return .unreachable }
        let text = try await presetsData()
        guard let presets = Self.parse(text), PresetsFileRepair.problem(text) == nil else {
            let repair = PresetsFileRepair.repair(text)
            return .presetsUnreadable(
                kept: repair.kept, dropped: repair.dropped, problem: PresetsFileRepair.problem(text) ?? ""
            )
        }
        let plans = PresetPackPlanner.planAll(packs, presets: presets, effects: effects)
        if plans.allSatisfy({ $0.plan.playlist == .skip }) { return .nothingAvailable }
        guard try await save(plans) else { return .unreachable }

        var ids: [String: Int] = [:]
        var created = 0
        var unavailable: [String] = []
        for (pack, plan) in plans {
            if let id = plan.playlist.playlistId { ids[pack.playlist.name] = id }
            created += plan.created.count
            if case .save = plan.playlist { created += 1 }
            for step in plan.unavailable where !unavailable.contains(step.name) { unavailable.append(step.name) }
        }
        let verified = created == 0 ? true : try await verify(plans)
        return .ready(
            playlistIds: ids, created: created, unavailable: unavailable, verified: verified,
            custom: DevicePresets(parsing: presets).custom
        )
    }

    /// Puts a built-in playlist and its effects back as the app defines them, which also plays it.
    /// - Returns: false if the device could not be reached or its presets.json could not be read.
    func reset(_ pack: PresetPack) async -> Bool {
        do {
            let effects = try JSONSerialization.jsonObject(with: try await get("/json/eff")) as? [String] ?? []
            guard !effects.isEmpty, let presets = try await readPresets() else { return false }
            let plan = PresetPackPlanner.reset(pack, presets: presets, effects: effects)
            return try await save([(pack, plan)])
        } catch {
            return false
        }
    }

    /// Starts a playlist (or preset) by id.
    func play(id: Int) async -> Bool {
        guard let body = try? PresetPackPayloads.playJSON(id: id) else { return false }
        return (try? await post(body)) ?? false
    }

    /// Sends one state call (save, delete or preview).
    func send(_ body: Data) async -> Bool {
        (try? await post(body)) ?? false
    }

    /// Carries out the plans: every new preset first, then the playlists, which refer to them. Each save
    /// gets time to be written, since back-to-back writes can damage presets.json.
    private func save(_ plans: [(pack: PresetPack, plan: PackPlan)]) async throws -> Bool {
        for (_, plan) in plans {
            for case .create(let name, let id, let effectId, let speed) in plan.presets {
                let body = try PresetPackPayloads.presetJSON(id: id, name: name, effectId: effectId, speed: speed)
                guard try await post(body) else { return false }
                try await Task.sleep(for: Self.presetGap)
            }
        }
        for (pack, plan) in plans {
            if case .save(let id, let presetIds) = plan.playlist {
                let body = try PresetPackPayloads.playlistJSON(pack.playlist, id: id, presetIds: presetIds)
                guard try await post(body) else { return false }
                try await Task.sleep(for: Self.playlistGap)
            }
        }
        return true
    }

    /// Reads presets.json back once. Planning again without any effects can only reuse what is on the
    /// device, so every playlist that was planned should now be found as is.
    private func verify(_ plans: [(pack: PresetPack, plan: PackPlan)]) async throws -> Bool {
        guard let presets = try await readPresets() else { return false }
        let after = PresetPackPlanner.planAll(plans.map(\.pack), presets: presets, effects: [])
        return zip(plans, after).allSatisfy { pair in
            if pair.0.plan.playlist == .skip { return true }
            if case .play = pair.1.plan.playlist { return true }
            return false
        }
    }

    private func presetsModified() async throws -> Int64? {
        let data = try await get("/json/info")
        let info = try? JSONDecoder().decode(Info.self, from: data)
        return info?.fileSystem?.presetLastModification.flatMap { $0 > 0 ? $0 : nil }
    }

    /// The device's presets, or nil if presets.json exists but cannot be parsed (an empty or cut-off file
    /// included). A device that never had a preset has no presets.json, which counts as empty.
    func readPresets() async throws -> [String: Any]? {
        Self.parse(try await presetsData())
    }

    private static func parse(_ data: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    /// presets.json as it is on the device; `{}` when it has none yet.
    private func presetsData() async throws -> Data {
        let (data, response) = try await URLSession.shared.data(
            for: URLRequest(url: try url("/presets.json"), timeoutInterval: 10)
        )
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 404 { return Data("{}".utf8) }
        guard (200..<300).contains(status) else { throw URLError(.badServerResponse) }
        return data
    }

    enum RepairResult {
        case repaired
        /// The file reads fine; nothing was uploaded.
        case notNeeded
        /// The device has a settings PIN that is not unlocked.
        case locked
        case failed
    }

    /// Replaces a damaged presets.json with the entries that are still intact (`PresetsFileRepair`),
    /// uploading it the way WLED's own backup restore does. Nothing is changed if the file reads fine.
    func repairPresets() async -> RepairResult {
        do {
            let text = try await presetsData()
            if PresetsFileRepair.problem(text) == nil { return .notNeeded }
            let repaired = try PresetsFileRepair.repair(text).json()
            let boundary = "SinagBoundary\(UUID().uuidString)"
            var body = Data()
            body.append(Data("--\(boundary)\r\n".utf8))
            body.append(Data("Content-Disposition: form-data; name=\"data\"; filename=\"/presets.json\"\r\n".utf8))
            body.append(Data("Content-Type: application/json\r\n\r\n".utf8))
            body.append(repaired)
            body.append(Data("\r\n--\(boundary)--\r\n".utf8))
            var request = URLRequest(url: try url("/upload"), timeoutInterval: 20)
            request.httpMethod = "POST"
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
            let (_, response) = try await URLSession.shared.data(for: request)
            await PresetCheckCache.shared.forget(address)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 401 { return .locked }
            guard (200..<300).contains(status) else { return .failed }
            try await Task.sleep(for: Self.playlistGap)
            return .repaired
        } catch {
            return .failed
        }
    }

    private func url(_ path: String) throws -> URL {
        guard let url = URL(string: "http://\(address)\(path)") else { throw URLError(.badURL) }
        return url
    }

    func get(_ path: String) async throws -> Data {
        try await URLSession.shared.data(for: URLRequest(url: try url(path), timeoutInterval: 10)).0
    }

    /// - Returns: true for a 2xx answer.
    private func post(_ body: Data) async throws -> Bool {
        var request = URLRequest(url: try url("/json/state"), timeoutInterval: 10)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        let (_, response) = try await URLSession.shared.data(for: request)
        return (200..<300).contains((response as? HTTPURLResponse)?.statusCode ?? 0)
    }
}
