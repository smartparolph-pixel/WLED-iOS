import Foundation

/// Makes the lantern's own page (WLED's web UI, shown in the device view) light or dark with the app.
///
/// WLED 0.15.3 has a built-in light theme. It keeps the choice in the page's storage on the phone
/// (`localStorage["wledUiCfg"].theme.base`, read when the page loads; `applyCfg()` applies a change), not on
/// the lantern, so this changes nothing on the lantern. Pages without it (e.g. the Config pages) are left
/// as they are.
enum WledPageTheme {
    static func script(light: Bool) -> String {
        let base = light ? "light" : "dark"
        return """
        (function () {
          try {
            var c = JSON.parse(localStorage.getItem('wledUiCfg') || '{}') || {};
            c.theme = c.theme || {};
            if (c.theme.base === '\(base)') return;
            c.theme.base = '\(base)';
            localStorage.setItem('wledUiCfg', JSON.stringify(c));
            if (window.cfg && window.cfg.theme && typeof window.applyCfg === 'function') {
              window.cfg.theme.base = '\(base)';
              window.applyCfg();
            }
          } catch (e) {}
        })();
        """
    }
}
