import AppKit
import SwiftUI
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var settingsWindowController: NSWindowController?
    private var timerCancellable: AnyCancellable?
    private let store = TimeZoneStore()

    func applicationDidFinishLaunching(_ notification: Notification) {
        store.openSettings = { [weak self] in
            self?.openSettingsWindow()
            if let popover = self?.popover, popover.isShown {
                popover.performClose(nil)
            }
        }
        setupStatusItem()
        setupPopover()
        startTimer()
        // Refresh immediately after system wakes from sleep
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleWake(_:)),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }

    @objc private func handleWake(_ notification: Notification) {
        store.now = Date()
        statusItem.button?.title = " " + store.menuBarText
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false   // Menu bar app: keep running after the last window closes
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }
        if let image = NSImage(systemSymbolName: "clock", accessibilityDescription: "TimeZoneBar") {
            image.isTemplate = true
            button.image = image
        }
        button.imagePosition = .imageLeft
        button.title = " " + store.menuBarText
        button.target = self
        button.action = #selector(togglePopover(_:))
    }

    private func setupPopover() {
        popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 330, height: 360)
        popover.contentViewController = NSHostingController(
            rootView: MenuPanelView().environmentObject(store)
        )
    }

    @objc private func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private func startTimer() {
        timerCancellable = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                // Combine sink closures are @Sendable and cannot touch MainActor state directly.
                // Timer.publish(..., on: .main) guarantees main-thread delivery, so
                // MainActor.assumeIsolated brings the compiler context back to the MainActor.
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.store.now = Date()
                    self.statusItem.button?.title = " " + self.store.menuBarText
                }
            }
    }

    private func openSettingsWindow() {
        if let existing = settingsWindowController {
            existing.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let host = NSHostingController(rootView: SettingsView().environmentObject(store))
        let window = NSWindow(contentViewController: host)
        window.title = "TimeZoneBar Settings"
        window.setContentSize(NSSize(width: 480, height: 460))
        window.styleMask = [.titled, .closable]
        window.center()
        let controller = NSWindowController(window: window)
        controller.showWindow(nil)
        settingsWindowController = controller
    }
}