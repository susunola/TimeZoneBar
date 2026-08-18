import AppKit

// Top-level code in main.swift runs on the main thread but outside MainActor isolation.
// NSApplication and AppDelegate are MainActor-isolated, so enter the MainActor via
// assumeIsolated before starting the run loop.
MainActor.assumeIsolated {
    let delegate = AppDelegate()
    NSApplication.shared.delegate = delegate
    // Dock app mode: regular activation policy so the app has a Dock icon.
    // Menu bar scene (com.apple.controlcenter.statusitems) requires a Team-ID
    // signed identity on macOS 26, which self-signed builds lack, so the Dock
    // icon is the primary entry point.
    NSApplication.shared.setActivationPolicy(.regular)
    NSApplication.shared.run()
}