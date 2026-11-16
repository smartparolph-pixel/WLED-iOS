import Testing
@testable import WLED

struct ApprovedFirmwareTests {
    @Test func noUpdateUntilANewerVersionIsApproved() {
        #expect(ApprovedFirmware.update(for: "0.15.3") == nil)
        #expect(!ApprovedFirmware.isApproved("v16.0.1"))
        #expect(ApprovedFirmware.isApproved("v0.15.3"))
    }

    @Test func approvedNewerVersionIsOfferedTheNewestOne() {
        let approved = ["v0.15.3", "v16.0.1", "v16.0.2"]
        #expect(ApprovedFirmware.update(for: "0.15.3", approved: approved) == "v16.0.2")
        #expect(ApprovedFirmware.update(for: "16.0.2", approved: approved) == nil)
        #expect(ApprovedFirmware.update(for: "16.0.9", approved: ["v16.0.10", "v16.0.2"]) == "v16.0.10")
    }

    @Test func olderLanternsAreBroughtUpToTheApprovedVersion() {
        #expect(ApprovedFirmware.update(for: "0.14.4") == "v0.15.3")
    }

    @Test func neverOffersDowngradesPreReleasesOrUnreadableVersions() {
        #expect(ApprovedFirmware.update(for: "16.0.1") == nil)
        #expect(ApprovedFirmware.update(for: "0.15.3", approved: ["v16.0.0-b2"]) == nil)
        #expect(ApprovedFirmware.update(for: "0.16.0-b1") == nil)
        #expect(ApprovedFirmware.update(for: nil) == nil)
        #expect(ApprovedFirmware.update(for: "") == nil)
        #expect(ApprovedFirmware.isApproved("v16.0", approved: ["v16.0.0"]))
    }
}
