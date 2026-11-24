import Foundation
import Testing
@testable import WLED

struct LanternWifiTests {
    @Test func nameShowsTheEndOfTheMac() {
        #expect(LanternWifi.ssid(forMac: "a0b1c2d3e4f5") == "Parol-E4F5")
        #expect(LanternWifi.ssid(forMac: "A0:B1:C2:D3:E4:F5") == "Parol-E4F5")
    }

    @Test func passwordIsEightEasyCharacters() {
        for _ in 0..<200 {
            let password = LanternWifi.newPassword()
            #expect(password.count == 8)
            #expect(password.allSatisfy { LanternWifi.alphabet.contains($0) })
            #expect(LanternWifi.isValidPassword(password))
        }
        #expect(!LanternWifi.alphabet.contains { "0o1li".contains($0) })
    }

    @Test func passwordsDifferBetweenLanterns() {
        let passwords = Set((0..<50).map { _ in LanternWifi.newCredentials(mac: "a0b1c2d3e4f5").password })
        #expect(passwords.count > 45)
    }

    @Test func wledNeedsAtLeastEightCharacters() {
        #expect(!LanternWifi.isValidPassword("12345"))
        #expect(LanternWifi.isValidPassword("k7m2q9xd"))
    }

    @Test func configSetsOnlyTheLanternWifi() throws {
        let credentials = LanternWifiCredentials(ssid: "Parol-E4F5", password: "k7m2q9xd")
        let json = String(decoding: try LanternWifi.configJSON(credentials), as: UTF8.self)
        #expect(json == "{\"ap\":{\"psk\":\"k7m2q9xd\",\"ssid\":\"Parol-E4F5\"}}")
        let withPin = try JSONSerialization.jsonObject(with: try LanternWifi.configJSON(credentials, pin: "1234")) as? [String: Any]
        #expect(withPin?["pin"] as? String == "1234")
    }

    @Test func setupSendsTheLanternWifi() throws {
        let ap: [String: Any] = ["ssid": "Parol-E4F5", "psk": "k7m2q9xd"]
        let data = try ProvisioningPayloads.wifiConfigJSON(ssid: "Home", password: "secret123", ap: ap)
        let cfg = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect((cfg?["ap"] as? [String: String]) == ["ssid": "Parol-E4F5", "psk": "k7m2q9xd"])
        let without = try ProvisioningPayloads.wifiConfigJSON(ssid: "Home", password: "secret123")
        #expect(!String(decoding: without, as: UTF8.self).contains("\"ap\""))
    }

    @Test func statusTellsSharedSecuredAndNotOnThisPhoneApart() {
        let saved = LanternWifiCredentials(ssid: "Parol-E4F5", password: "k7m2q9xd")
        #expect(LanternWifi.status(ssid: nil, passwordLength: nil, saved: saved) == .unknown)
        #expect(LanternWifi.status(ssid: "WLED-AP", passwordLength: 8, saved: nil) == .shared)
        #expect(LanternWifi.status(ssid: "Parol-E4F5", passwordLength: 8, saved: saved) == .secured)
        #expect(LanternWifi.status(ssid: "Parol-E4F5", passwordLength: 8, saved: nil) == .notOnThisPhone)
        #expect(LanternWifi.status(ssid: "Parol-E4F5", passwordLength: 12, saved: saved) == .notOnThisPhone)
    }

    @Test func readsWhatWledReports() {
        let reported = LanternWifi.fromConfig(["ap": ["ssid": "WLED-AP", "pskl": 8, "chan": 1]])
        #expect(reported.ssid == "WLED-AP")
        #expect(reported.passwordLength == 8)
    }
}
