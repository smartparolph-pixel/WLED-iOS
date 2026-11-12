import Foundation
import Testing
@testable import WLED

struct ProvisioningPayloadsTests {

    @Test func wifiConfigJSONOnlyTouchesFirstNetworkEntry() throws {
        let data = try ProvisioningPayloads.wifiConfigJSON(ssid: "Home WiFi", password: "p@ss\"word")
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let nw = try #require(object["nw"] as? [String: Any])
        let ins = try #require(nw["ins"] as? [[String: String]])
        #expect(object.keys.sorted() == ["nw"])
        #expect(nw.keys.sorted() == ["ins"])
        #expect(ins.count == 1)
        #expect(ins[0]["ssid"] == "Home WiFi")
        #expect(ins[0]["psk"] == "p@ss\"word")
    }

    @Test func rebootPayloadIsValidJSON() throws {
        let object = try #require(try JSONSerialization.jsonObject(with: ProvisioningPayloads.rebootJSON) as? [String: Bool])
        #expect(object == ["rb": true])
    }

    @Test func sameMacIgnoresCaseAndSeparators() {
        #expect(ProvisioningPayloads.sameMac("AA:BB:CC:DD:EE:FF", "aabbccddeeff"))
        #expect(ProvisioningPayloads.sameMac("aa-bb-cc-dd-ee-ff", "AABBCCDDEEFF"))
    }

    @Test func sameMacRejectsMissingOrDifferent() {
        #expect(!ProvisioningPayloads.sameMac(nil, "aabbccddeeff"))
        #expect(!ProvisioningPayloads.sameMac("", ""))
        #expect(!ProvisioningPayloads.sameMac("aabbccddeeff", "aabbccddee00"))
    }

    @Test func powerLimitSetsTheTotalAndEachOutputWithEverythingElseKept() throws {
        // hw.led as WLED 0.15.3 writes it for a lantern: one output of 160 LEDs, limited to 850 mA.
        let cfg = try #require(try JSONSerialization.jsonObject(with: Data(#"""
        {"hw":{"led":{"total":160,"maxpwr":850,"ins":[{"start":0,"len":160,"pin":[2],"order":0,"rev":false,
         "skip":0,"type":22,"ref":false,"rgbwm":0,"freq":0,"maxpwr":850,"ledma":55}]}}}
        """#.utf8)) as? [String: Any])
        let led = try #require(ProvisioningPayloads.powerLimitConfig(cfg))
        let data = try ProvisioningPayloads.wifiConfigJSON(ssid: "Home", password: "secret123", led: led)
        let body = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let sentLed = try #require((body["hw"] as? [String: Any])?["led"] as? [String: Any])
        #expect(sentLed["maxpwr"] as? Int == 2000)
        let output = try #require((sentLed["ins"] as? [[String: Any]])?.first)
        #expect(output["maxpwr"] as? Int == 2000)
        #expect(output["len"] as? Int == 160)
        #expect(output["pin"] as? [Int] == [2])
        #expect(output["type"] as? Int == 22)
        #expect(output["ledma"] as? Int == 55)
        #expect(output["rev"] as? Bool == false)
        #expect(output.count == 12)
        #expect(body["nw"] != nil)
    }

    @Test func powerLimitIsSplitAcrossOutputsByLedCount() throws {
        let cfg = try #require(try JSONSerialization.jsonObject(with: Data(
            #"{"hw":{"led":{"ins":[{"len":100,"pin":[2]},{"len":60,"pin":[4]},{"len":40,"pin":[5]}]}}}"#.utf8
        )) as? [String: Any])
        let ins = try #require(ProvisioningPayloads.powerLimitConfig(cfg)?["ins"] as? [[String: Any]])
        #expect(ins.map { $0["maxpwr"] as? Int } == [1000, 600, 400])
    }

    @Test func powerLimitChangesNothingWithoutOutputs() {
        #expect(ProvisioningPayloads.powerLimitConfig(["hw": ["led": [String: Any]()]]) == nil)
        #expect(ProvisioningPayloads.powerLimitConfig([:]) == nil)
    }

    @Test func deviceNameIsSavedOnTheDevice() throws {
        let data = try ProvisioningPayloads.wifiConfigJSON(ssid: "Home", password: "secret123", name: "Living Room Parol")
        let body = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect((body["id"] as? [String: Any])?["name"] as? String == "Living Room Parol")
        let blank = try ProvisioningPayloads.wifiConfigJSON(ssid: "Home", password: "secret123", name: " ")
        let blankBody = try #require(try JSONSerialization.jsonObject(with: blank) as? [String: Any])
        #expect(blankBody["id"] == nil)
    }

    @Test func shareLinkRoundTrips() throws {
        let url = try #require(URL(string: ParolShareLink.url(address: "192.168.68.60")))
        #expect(ParolShareLink.address(from: url) == "192.168.68.60")
        #expect(ParolShareLink.address(from: try #require(URL(string: "https://example.com"))) == nil)
    }
}
