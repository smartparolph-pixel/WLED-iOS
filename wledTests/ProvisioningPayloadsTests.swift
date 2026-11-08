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
        #expect(String(data: data, encoding: .utf8) == #"{"hw":{"led":{"ins":[{"freq":0,"len":160,"ledma":55,"maxpwr":2000,"order":0,"pin":[2],"ref":false,"rev":false,"rgbwm":0,"skip":0,"start":0,"type":22}],"maxpwr":2000}},"nw":{"ins":[{"psk":"secret123","ssid":"Home"}]}}"#)
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
}
