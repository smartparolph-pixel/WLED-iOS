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
}
