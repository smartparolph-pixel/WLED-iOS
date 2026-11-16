import Foundation
import Testing
@testable import WLED

struct DirectConnectionTests {
    @Test func phoneOnTheLanternWifi() {
        #expect(DirectConnection.isOnLanternNetwork(addresses: ["127.0.0.1", "4.3.2.2"]))
        #expect(!DirectConnection.isOnLanternNetwork(addresses: ["127.0.0.1", "192.168.1.20"]))
        #expect(!DirectConnection.isOnLanternNetwork(addresses: []))
    }

    @Test func lanternAddressNeverReplacesTheSavedOne() {
        #expect(DirectConnection.addressToSave(saved: "192.168.1.60", newAddress: "4.3.2.1") == "192.168.1.60")
        #expect(DirectConnection.addressToSave(saved: "192.168.1.60", newAddress: "192.168.1.75") == "192.168.1.75")
        #expect(DirectConnection.addressToSave(saved: nil, newAddress: "4.3.2.1") == "4.3.2.1")
        #expect(DirectConnection.addressToSave(saved: "", newAddress: "4.3.2.1") == "4.3.2.1")
    }

    @Test func macsMatchWhateverTheirFormat() {
        #expect(DirectConnection.sameMac("a0b1c2d3e4f5", "A0:B1:C2:D3:E4:F5"))
        #expect(!DirectConnection.sameMac("a0b1c2d3e4f5", "112233445566"))
        #expect(!DirectConnection.sameMac(nil, "a0b1c2d3e4f5"))
        #expect(!DirectConnection.sameMac("", ""))
    }

    @Test func timeIsSentAsWholeSeconds() {
        #expect(DirectConnection.timeJSON(Date(timeIntervalSince1970: 1_763_251_200.7)) == "{\"time\":1763251200}")
    }
}
