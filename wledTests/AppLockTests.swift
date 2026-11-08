import Testing
@testable import WLED

struct AppLockTests {
    @Test func defaultRelocksAfterTwoMinutesInTheBackground() {
        #expect(!AppLockPolicy.shouldLockOnReturn(enabled: true, backgroundedAt: 0, now: 119, timeout: .twoMinutes))
        #expect(AppLockPolicy.shouldLockOnReturn(enabled: true, backgroundedAt: 0, now: 120, timeout: .twoMinutes))
    }

    @Test func immediatelyAndFiveMinutes() {
        #expect(AppLockPolicy.shouldLockOnReturn(enabled: true, backgroundedAt: 10, now: 10, timeout: .immediately))
        #expect(!AppLockPolicy.shouldLockOnReturn(enabled: true, backgroundedAt: 0, now: 299, timeout: .fiveMinutes))
        #expect(AppLockPolicy.shouldLockOnReturn(enabled: true, backgroundedAt: 0, now: 300, timeout: .fiveMinutes))
    }

    @Test func neverLocksWhenOffOrNotBackgrounded() {
        #expect(!AppLockPolicy.shouldLockOnReturn(enabled: false, backgroundedAt: 0, now: 600, timeout: .immediately))
        #expect(!AppLockPolicy.shouldLockOnReturn(enabled: true, backgroundedAt: nil, now: 600, timeout: .immediately))
    }
}
