import AppKit
import SwiftUI
import Combine

/// Borderless panel used for the main window. Being borderless it bypasses
/// the macOS 26 FrontBoard scene-fence that refuses to render titled windows
/// for self-signed (no Team ID) apps. We draw our own rounded squircle
/// background + traffic lights in SwiftUI. `canBecomeKey` is required for a
/// borderless window to accept clicks and become the key window.
@MainActor
private final class BorderlessPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    // Accept first responder for keyboard shortcuts (Cmd+W etc.)
    override var acceptsFirstResponder: Bool { true }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    // Menu bar status item — best-effort. On macOS 26 the scene manager may
    // not display this for self-signed/ad-hoc builds (no Team ID), but we
    // still try — when it does work, the user can click it to open the panel.
    private var statusItem: NSStatusItem?

    // Primary UI: a regular NSWindow with .utilityWindow style. macOS 26
    // applies the system corner radius to it (smaller than the macOS 26
    // squircle, but it's the only style that consistently renders for
    // self-signed apps). We deliberately stay away from borderless and
    // transparent-titlebar variants because both trip the macOS 26
    // FrontBoard scene fence for self-signed builds.
    private var panel: NSWindow!

    private var settingsWindowController: NSWindowController?
    private var timerCancellable: AnyCancellable?
    private let store = TimeZoneStore()

    func applicationDidFinishLaunching(_ notification: Notification) {
        store.openSettings = { [weak self] in
            self?.openSettingsWindow()
        }
        store.onZonesChanged = { [weak self] in
            self?.updatePanelHeight()
        }
        store.chooseAvatar = { [weak self] in
            self?.chooseAvatarFile()
        }
        store.closeWindow = { [weak self] in
            self?.panel.orderOut(nil)
        }
        store.minimizeWindow = { [weak self] in
            self?.panel.miniaturize(nil)
        }
        store.zoomWindow = { [weak self] in
            // Green traffic light: toggle zoom (maximize / restore). For a
            // borderless panel, performZoom() is the closest system match.
self?.panel.performZoom(nil)
        }
        setupStatusItem()
        setupPanel()
        startTimer()
        // Do NOT auto-show the panel on launch — in Dock mode the app opens
        // quietly and the user opens the window by clicking the Dock icon.
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleWake(_:)),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }

    /// Grows / shrinks the window so it exactly fits the number of zone rows.
    private func updatePanelHeight() {
        let rowHeights: [Theme: CGFloat] = [.minimal: 52, .glass: 82, .midnight: 52, .editorial: 66]
        let rowH = rowHeights[store.theme] ?? 60
        // header (~180-240) + list top/bottom padding (~20) + footer (~150)
        let fixedChrome: CGFloat = store.theme == .editorial ? 400 : 360
        let wanted = fixedChrome + CGFloat(store.zones.count) * rowH + 24
        let width = panel.frame.width
        panel.setContentSize(NSSize(width: width, height: max(460, wanted)))
        panel.layoutIfNeeded()
    }

    @objc private func handleWake(_ notification: Notification) {
        store.now = Date()
        statusItem?.button?.title = " " + store.menuBarText
    }

    // Dock icon click → show / hide the panel
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        togglePanel()
        return true
    }

    // Closing the window does not quit the app — the Dock icon stays and
    // clicking it reopens the panel.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            if let image = NSImage(systemSymbolName: "clock", accessibilityDescription: "TravelTime") {
                image.isTemplate = true
                button.image = image
            }
            button.imagePosition = .imageLeft
            button.title = " " + store.menuBarText
            button.target = self
            button.action = #selector(statusItemClicked(_:))
        }
        self.statusItem = item
    }

    @objc private func statusItemClicked(_ sender: AnyObject?) {
        togglePanel()
    }

    private func setupPanel() {
        let width: CGFloat = 400
        let height: CGFloat = 640

        // utilityWindow style: this is the combination the user has confirmed
        // actually renders on this machine. Borderless NSPanel and any
        // titlebar-true variants get blocked by the macOS 26 FrontBoard
        // scene fence for self-signed (no Team ID) apps.
        let p = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.titled, .closable, .resizable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        p.title = "TravelTime"
        p.level = .normal
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.minSize = NSSize(width: 360, height: 460)
        p.setContentSize(NSSize(width: width, height: height))

        let hosting = NSHostingView(rootView: MenuPanelView().environmentObject(store))
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: height)
        hosting.autoresizingMask = [.width, .height]
        p.contentView = hosting
        p.center()
        self.panel = p
    }

    private func togglePanel() {
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            showPanel()
        }
    }

    private func showPanel() {
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func startTimer() {
        timerCancellable = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                // Timer.publish(..., on: .main) guarantees main-thread delivery
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.store.now = Date()
                    self.statusItem?.button?.title = " " + self.store.menuBarText
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
        window.title = "TravelTime Settings"
        window.setContentSize(NSSize(width: 480, height: 460))
        window.styleMask = [.titled, .closable]
        window.center()
        let controller = NSWindowController(window: window)
        controller.showWindow(nil)
        settingsWindowController = controller
    }

    /// Open panel for picking a custom avatar. The picked image is copied
    /// into Application Support/TravelTime/avatar.jpg and the store reloads
    /// its avatar path so the panel updates.
    private func chooseAvatarFile() {
        let panel = NSOpenPanel()
        panel.title = "Choose Avatar"
        panel.prompt = "Choose"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.image]   // any image

        // Run modally; if user picks, copy into Application Support.
        let response = panel.runModal()
        guard response == .OK, let src = panel.url else { return }

        do {
            let fm = FileManager.default
            let support = try fm.url(for: .applicationSupportDirectory,
                                      in: .userDomainMask,
                                      appropriateFor: nil,
                                      create: true)
            let dir = support.appendingPathComponent("TravelTime", isDirectory: true)
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            let dst = dir.appendingPathComponent("avatar.jpg")

            // Replace any existing avatar atomically.
            if fm.fileExists(atPath: dst.path) {
                try fm.removeItem(at: dst)
            }
            try fm.copyItem(at: src, to: dst)

            store.reloadAvatar()
        } catch {
            NSAlert(error: error).runModal()
        }
    }
}
