// Spec 037 — dummy test-host app (research R2).
//
// Xcode's ui-testing product type requires a runnable host target; the
// tests ignore this app entirely and drive JuraDrop by bundle id. This
// stub never ships, never shows UI (accessory activation policy), and
// exists only to satisfy the toolchain.

import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
app.run()
