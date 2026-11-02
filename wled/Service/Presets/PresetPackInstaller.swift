import Foundation

enum PackSetupResult: Equatable {
    /// - Parameters:
    ///   - playlistIds: Preset id of each pack's playlist on the device, keyed by playlist name.
    ///   - created: Number of presets and playlists saved now (0 when everything was already there).
    ///   - unavailable: Effects that could not be added (missing in the firmware or no free slot).
    ///   - verified: Everything was found in presets.json afterwards.
    case ready(playlistIds: [String: Int], created: Int, unavailable: [String], verified: Bool)
    /// None of the packs' effects exist on the device, or it has no free preset slots.
    case nothingAvailable
    case unreachable

    /// Effects that could not be added, and a warning if the device did not confirm the saves.
    var notes: String? {
        guard case .ready(_, _, let unavailable, let verified) = self else { return nil }
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
        case .unreachable:
            return String(localized: "Could not reach the device. Make sure it is on and try again.")
        }
    }
}

/// Makes sure every `PresetPack` is on a device, without asking: missing presets and playlists are added,
/// those already there (matched by name) are left alone, so it is safe to run every time.
struct PresetPackInstaller {
    /// Gives the device time to write presets.json between saves; back-to-back writes can corrupt it.
    private static let saveGap: Duration = .milliseconds(500)

    let address: String

    /// Saving a preset or playlist also applies it to the lights, so the lights change while anything is
    /// added. Afterwards `play` is started if given, or `PresetPacks.playsAfterSetup` if anything was added,
    /// so the device never ends on a random effect.
    func ensureAll(play: PresetPack? = nil, packs: [PresetPack] = PresetPacks.all) async -> PackSetupResult {
        do {
            let effects = try JSONSerialization.jsonObject(with: try await get("/json/eff")) as? [String] ?? []
            guard !effects.isEmpty else { return .unreachable }
            let plans = PresetPackPlanner.planAll(packs, presets: try await readPresets(), effects: effects)
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
            let start = play ?? (created > 0 ? PresetPacks.playsAfterSetup : nil)
            if let start, let id = ids[start.playlist.name] {
                _ = try await post(try PresetPackPayloads.playJSON(id: id))
            }
            let verified = created == 0 ? true : try await verify(plans)
            return .ready(playlistIds: ids, created: created, unavailable: unavailable, verified: verified)
        } catch {
            return .unreachable
        }
    }

    /// Starts a playlist (or preset) by id.
    func play(id: Int) async -> Bool {
        guard let body = try? PresetPackPayloads.playJSON(id: id) else { return false }
        return (try? await post(body)) ?? false
    }

    /// Carries out the plans: new presets first, then each playlist.
    private func save(_ plans: [(pack: PresetPack, plan: PackPlan)]) async throws -> Bool {
        for (pack, plan) in plans {
            var bodies: [Data] = []
            for case .create(let name, let id, let effectId) in plan.presets {
                bodies.append(try PresetPackPayloads.presetJSON(id: id, name: name, effectId: effectId))
            }
            if case .save(let id, let presetIds) = plan.playlist {
                bodies.append(try PresetPackPayloads.playlistJSON(pack.playlist, id: id, presetIds: presetIds))
            }
            for body in bodies {
                guard try await post(body) else { return false }
                try await Task.sleep(for: Self.saveGap)
            }
        }
        return true
    }

    /// Reads presets.json back once. Planning again without any effects can only reuse what is on the
    /// device, so every playlist that was planned should now be found as is.
    private func verify(_ plans: [(pack: PresetPack, plan: PackPlan)]) async throws -> Bool {
        let after = PresetPackPlanner.planAll(plans.map(\.pack), presets: try await readPresets(), effects: [])
        return zip(plans, after).allSatisfy { pair in
            if pair.0.plan.playlist == .skip { return true }
            if case .play = pair.1.plan.playlist { return true }
            return false
        }
    }

    private func readPresets() async throws -> [String: Any] {
        (try JSONSerialization.jsonObject(with: try await get("/presets.json")) as? [String: Any]) ?? [:]
    }

    private func url(_ path: String) throws -> URL {
        guard let url = URL(string: "http://\(address)\(path)") else { throw URLError(.badURL) }
        return url
    }

    private func get(_ path: String) async throws -> Data {
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
