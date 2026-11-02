import Foundation

enum PackInstallResult: Equatable {
    /// - Parameters:
    ///   - created: Names of the presets added now.
    ///   - unavailable: Names that could not be added (effect missing or no free slot).
    ///   - verified: The presets and playlist were found on the device afterwards.
    case done(playlistName: String, created: [String], unavailable: [String], verified: Bool)
    /// None of the pack's effects exist on the device, or it has no free preset slots.
    case nothingAvailable
    case unreachable

    /// One line describing what adding a pack did, e.g. "✨ Twinkle Tonight was added and is playing now."
    var message: String {
        switch self {
        case .done(let playlistName, let created, let unavailable, let verified):
            var parts = [created.isEmpty
                ? String(localized: "\(playlistName) is already on this device and is playing now.")
                : String(localized: "\(playlistName) was added and is playing now.")]
            if !unavailable.isEmpty {
                parts.append(String(localized: "Not available on this device: \(unavailable.joined(separator: ", "))."))
            }
            if !verified {
                parts.append(String(localized: "The device did not confirm every preset; check its Presets list."))
            }
            return parts.joined(separator: " ")
        case .nothingAvailable:
            return String(localized: "Nothing could be added: this device has none of these effects or no free preset slots.")
        case .unreachable:
            return String(localized: "Could not reach the device. Make sure it is on and try again.")
        }
    }
}

/// One pack's result from `installAll`.
struct PackOutcome: Equatable {
    let pack: PresetPack
    let result: PackInstallResult

    /// What "Add all" did, e.g. "Playlists added: 10. ✨ Twinkle Tonight is playing now.", followed by
    /// anything that could not be added.
    static func summary(_ outcomes: [PackOutcome]) -> String {
        var done: [(pack: PresetPack, unavailable: [String], verified: Bool)] = []
        for outcome in outcomes {
            if case .done(_, _, let unavailable, let verified) = outcome.result {
                done.append((outcome.pack, unavailable, verified))
            }
        }
        guard !done.isEmpty else { return (outcomes.first?.result ?? .unreachable).message }
        let playing = (done.first { $0.pack == PresetPacks.playsAfterSetup } ?? done[done.count - 1]).pack
        var parts = [String(localized: "Playlists added: \(done.count). \(playing.playlist.name) is playing now.")]
        var unavailable: [String] = []
        for name in done.flatMap(\.unavailable) where !unavailable.contains(name) { unavailable.append(name) }
        if !unavailable.isEmpty {
            parts.append(String(localized: "Not available on this device: \(unavailable.joined(separator: ", "))."))
        }
        let notAdded = outcomes
            .filter { if case .done = $0.result { return false } else { return true } }
            .map(\.pack.playlist.name)
            .joined(separator: ", ")
        if !notAdded.isEmpty {
            parts.append(String(localized: "Could not add: \(notAdded)."))
        }
        if done.contains(where: { !$0.verified }) {
            parts.append(String(localized: "The device did not confirm every preset; check its Presets list."))
        }
        return parts.joined(separator: " ")
    }
}

/// Adds a `PresetPack` to a device and starts its playlist. Safe to run again: presets and playlists
/// already on the device (matched by name) are reused, so nothing is duplicated.
struct PresetPackInstaller {
    /// Gives the device time to write presets.json between saves; back-to-back writes can corrupt it.
    private static let saveGap: Duration = .milliseconds(500)

    let address: String

    /// Adds every pack, `finish` last so its playlist is the one left playing. Results are in the order of
    /// `packs`. Stops early if the device cannot be reached.
    func installAll(
        _ packs: [PresetPack] = PresetPacks.all,
        finish: PresetPack = PresetPacks.playsAfterSetup
    ) async -> [PackOutcome] {
        var results: [String: PackInstallResult] = [:]
        for pack in packs.filter({ $0 != finish }) + packs.filter({ $0 == finish }) {
            let result = await install(pack)
            results[pack.playlist.name] = result
            if result == .unreachable { break }
        }
        return packs.map { PackOutcome(pack: $0, result: results[$0.playlist.name] ?? .unreachable) }
    }

    func install(_ pack: PresetPack) async -> PackInstallResult {
        do {
            let effects = try JSONSerialization.jsonObject(with: try await get("/json/eff")) as? [String] ?? []
            guard !effects.isEmpty else { return .unreachable }
            let plan = PresetPackPlanner.plan(pack, presets: try await readPresets(), effects: effects)
            if plan.playlist == .skip { return .nothingAvailable }

            for step in plan.presets {
                guard case .create(let name, let id, let effectId) = step else { continue }
                guard try await post(try PresetPackPayloads.presetJSON(id: id, name: name, effectId: effectId)) else {
                    return .unreachable
                }
                try await Task.sleep(for: Self.saveGap)
            }
            switch plan.playlist {
            case .save(let id, let presetIds):
                _ = try await post(try PresetPackPayloads.playlistJSON(pack.playlist, id: id, presetIds: presetIds))
            case .play(let id):
                _ = try await post(try PresetPackPayloads.playJSON(id: id))
            case .skip:
                break
            }
            try await Task.sleep(for: Self.saveGap)

            return .done(
                playlistName: pack.playlist.name,
                created: plan.created.map(\.name),
                unavailable: plan.unavailable.map(\.name),
                verified: try await verify(plan, pack)
            )
        } catch {
            return .unreachable
        }
    }

    /// Reads presets.json back. Planning again without any effects can only reuse what is on the device,
    /// so every preset should come back as reused and the playlist as "just play it".
    private func verify(_ plan: PackPlan, _ pack: PresetPack) async throws -> Bool {
        let after = PresetPackPlanner.plan(pack, presets: try await readPresets(), effects: [])
        let expected = Set((plan.created + plan.reused).map(\.name))
        guard Set(after.reused.map(\.name)) == expected else { return false }
        if case .play = after.playlist { return true }
        return false
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
