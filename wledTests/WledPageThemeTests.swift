import Testing
@testable import WLED

struct WledPageThemeTests {
    @Test func setsWledsOwnThemeSettingOnThePhone() {
        let light = WledPageTheme.script(light: true)
        #expect(light.contains("localStorage.setItem('wledUiCfg'"))
        #expect(light.contains("c.theme.base = 'light'"))
        #expect(light.contains("window.applyCfg()"))
        let dark = WledPageTheme.script(light: false)
        #expect(dark.contains("c.theme.base = 'dark'"))
        #expect(!dark.contains("'light'"))
    }

    @Test func appearanceFollowsTheIPhoneByDefault() {
        #expect(AppAppearance.system.colorScheme == nil)
        #expect(AppAppearance.light.colorScheme == .light)
        #expect(AppAppearance.dark.colorScheme == .dark)
    }
}
