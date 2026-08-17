import AppKit

// Top-level code in main.swift runs on the main thread but outside MainActor isolation.
// NSApplication and AppDelegate are MainActor-isolated, so enter the MainActor via
// assumeIsolated before starting the run loop.
MainActor.assumeIsolated {
    let delegate = AppDelegate()
    NSApplication.shared.delegate = delegate
    NSApplication.shared.setActivationPolicy(.accessory)
    NSApplication.shared.run()
}