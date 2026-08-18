import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @EnvironmentObject var store: TimeZoneStore
    @StateObject private var updater = Updater()
    @State private var addSelection = 0
    @State private var launchAtLogin = false
    @State private var showUninstallConfirm = false
    @State private var isUninstalling = false

    private var isBundled: Bool { Bundle.main.bundleIdentifier != nil }

    private var updateStatusText: String {
        switch updater.state {
        case .idle: return "Check GitHub for a new version"
        case .checking: return "Checking…"
        case .available(let v, _): return "Version \(v) is available — click Update to install it in place"
        case .downloading: return "Downloading and installing, the app will relaunch…"
        case .upToDate: return "You are running the latest version"
        case .error(let msg): return msg
        }
    }

    private var updateButtonTitle: String { updater.state.buttonTitle }

    static let commonZones: [(id: String, label: String, region: String)] = [
        ("Asia/Shanghai", "Beijing / Shanghai", "China"),
        ("Asia/Bangkok", "Bangkok", "Thailand"),
        ("Asia/Jakarta", "Jakarta", "Indonesia"),
        ("Asia/Hong_Kong", "Hong Kong", "China"),
        ("Asia/Taipei", "Taipei", "Taiwan, China"),
        ("Asia/Tokyo", "Tokyo", "Japan"),
        ("Asia/Seoul", "Seoul", "South Korea"),
        ("Asia/Singapore", "Singapore", "Singapore"),
        ("Asia/Dubai", "Dubai", "UAE"),
        ("Asia/Kolkata", "New Delhi", "India"),
        ("Australia/Sydney", "Sydney", "Australia"),
        ("Pacific/Auckland", "Auckland", "New Zealand"),
        ("Europe/London", "London", "United Kingdom"),
        ("Europe/Paris", "Paris", "France"),
        ("Europe/Berlin", "Berlin", "Germany"),
        ("Europe/Berlin", "Frankfurt", "Germany"),
        ("Europe/Madrid", "Madrid", "Spain"),
        ("Europe/Rome", "Rome", "Italy"),
        ("Europe/Amsterdam", "Amsterdam", "Netherlands"),
        ("America/New_York", "New York", "United States"),
        ("America/Los_Angeles", "Los Angeles", "United States"),
        ("America/Chicago", "Chicago", "United States"),
        ("America/Sao_Paulo", "São Paulo", "Brazil"),
        ("UTC", "Coordinated Universal Time", "")
    ]

    /// The Settings picker keeps every common zone (including Berlin AND
    /// Frankfurt — same IANA id, different cities) selectable via index tags.
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("TravelTime Settings")
                    .font(.title2)
                    .padding(.bottom, 2)

                // General
                SettingsCard {
                    if isBundled {
                        Toggle("Launch at login", isOn: $launchAtLogin)
                            .onChange(of: launchAtLogin) { _, newValue in
                                do {
                                    if newValue {
                                        try SMAppService.mainApp.register()
                                    } else {
                                        try SMAppService.mainApp.unregister()
                                    }
                                } catch {
                                    launchAtLogin = !newValue
                                    let alert = NSAlert()
                                    alert.messageText = "Failed to \(newValue ? "enable" : "disable") launch at login"
                                    alert.informativeText = error.localizedDescription
                                    alert.alertStyle = .warning
                                    alert.runModal()
                                }
                            }
                    }
                }

                // Time zones
                SettingsCard(title: "Time Zones") {
                    HStack(spacing: 8) {
                        Picker("Add a time zone", selection: $addSelection) {
                            // Index tags keep Berlin & Frankfurt (same tz id,
                            // different names) both selectable.
                            ForEach(Array(Self.commonZones.enumerated()), id: \.offset) { i, item in
                                Text(item.region.isEmpty ? item.label : "\(item.label) · \(item.region)")
                                    .tag(i)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 220)

                        Button("Add") {
                            guard addSelection < Self.commonZones.count else { return }
                            let item = Self.commonZones[addSelection]
                            // Dedupe by (id, label) — the same rule as the main
                            // panel, so Berlin and Frankfurt can both exist.
                            guard !store.zones.contains(where: { $0.id == item.id && $0.label == item.label }) else { return }
                            store.zones.append(ZoneEntry(id: item.id,
                                                         label: item.label,
                                                         region: item.region,
                                                         color: store.nextZoneColor()))
                        }
                        .disabled(addSelection >= Self.commonZones.count
                                  || store.zones.contains {
                                      $0.id == Self.commonZones[addSelection].id
                                          && $0.label == Self.commonZones[addSelection].label
                                  })
                    }

                    ForEach(store.zones, id: \.uuid) { zone in
                        HStack {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color(hex: zone.color))
                                .frame(width: 4, height: 16)
                            Text("\(zone.label) (\(zone.id))")
                                .font(.system(size: 13))
                                .lineLimit(1)
                            Spacer()
                            if zone.uuid == store.currentZoneUUID {
                                Text("Current")
                                    .font(.system(size: 11))
                                    .foregroundColor(.blue)
                            }
                            Button("Remove") {
                                store.zones.removeAll { $0.uuid == zone.uuid }
                            }
                            .disabled(zone.uuid == store.currentZoneUUID)
                            .accessibilityLabel("Remove \(zone.label)")
                        }
                        .padding(.vertical, 2)
                    }

                    Button("Restore Defaults") {
                        store.zones = TimeZoneStore.defaultZones
                    }
                    .padding(.top, 4)
                }

                // Display
                SettingsCard(title: "Display") {
                    Toggle("Show date in the menu bar", isOn: $store.showDateInMenuBar)

                    HStack {
                        Text("Time format")
                            .font(.system(size: 13))
                        Spacer()
                        Picker("Time format", selection: $store.use24Hour) {
                            Text("24-hour").tag(true)
                            Text("12-hour").tag(false)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 180)
                    }
                }

                // Appearance (theme)
                SettingsCard(title: "Appearance") {
                    Text("Choose how the main panel looks. Changes apply immediately.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)

                    ForEach(Theme.allCases) { theme in
                        Button {
                            store.theme = theme
                        } label: {
                            HStack(spacing: 10) {
                                ThemeSwatch(theme: theme)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(theme.displayName)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(.primary)
                                    Text(themeDescription(theme))
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                if store.theme == theme {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 15))
                                        .foregroundColor(.blue)
                                }
                            }
                            .padding(8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(store.theme == theme ? Color.blue.opacity(0.08) : Color.clear)
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }

                // Software update
                SettingsCard {
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.down.circle")
                            .font(.system(size: 13))
                            .foregroundColor(.blue)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Software Update")
                                .font(.system(size: 13, weight: .medium))
                            Text(updateStatusText)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Button(updateButtonTitle) {
                            switch updater.state {
                            case .available(_, let release):
                                Task { await updater.update(release: release) }
                            default:
                                Task { await updater.check() }
                            }
                        }
                        .disabled(updater.isBusy)
                    }
                }

                // Uninstall
                SettingsCard {
                    HStack(spacing: 10) {
                        Image(systemName: "trash")
                            .font(.system(size: 13))
                            .foregroundColor(.red)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Uninstall TravelTime")
                                .font(.system(size: 13, weight: .medium))
                            Text("Removes the app and all local data (requires authorization)")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Button("Uninstall…", role: .destructive) {
                            showUninstallConfirm = true
                        }
                        .disabled(isUninstalling)
                    }
                    .confirmationDialog("Uninstall TravelTime?",
                                        isPresented: $showUninstallConfirm,
                                        titleVisibility: .visible) {
                        Button("Uninstall and Delete Data", role: .destructive) {
                            uninstall()
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("The app will be deleted and quit immediately. If the icon lingers in Launchpad, run killall Dock in Terminal or log out and back in.")
                    }
                }
            }
            .padding(20)
            .frame(width: 480)
        }
        .onAppear {
            if isBundled {
                launchAtLogin = (SMAppService.mainApp.status == .enabled)
            }
        }
    }

    /// Uninstall: clear all local data, deregister login item, delete the bundle, then quit
    private func uninstall() {
        guard !isUninstalling else { return }
        isUninstalling = true

        let fm = FileManager.default
        let home = NSHomeDirectory()
        let bundleID = Bundle.main.bundleIdentifier ?? "com.atom.tzbar"

        // 1. UserDefaults (preferences)
        UserDefaults.standard.removePersistentDomain(forName: bundleID)
        // Also remove the plist file directly in case it lingers
        let prefsPlist = "\(home)/Library/Preferences/\(bundleID).plist"
        try? fm.removeItem(atPath: prefsPlist)

        // 2. Application Support
        if let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("TravelTime", isDirectory: true) {
            try? fm.removeItem(at: appSupport)
        }

        // 3. Caches
        if let cachesDir = fm.urls(for: .cachesDirectory, in: .userDomainMask).first {
            try? fm.removeItem(at: cachesDir.appendingPathComponent(bundleID))
            try? fm.removeItem(at: cachesDir.appendingPathComponent("TravelTime"))
        }

        // 4. Saved Application State (window restore)
        let savedState = "\(home)/Library/Saved Application State/\(bundleID).savedState"
        try? fm.removeItem(atPath: savedState)

        // 5. HTTPStorages (URLSession cookies/cache)
        let httpStorages = "\(home)/Library/HTTPStorages/\(bundleID)"
        try? fm.removeItem(atPath: httpStorages)

        // 6. Logs
        try? fm.removeItem(atPath: "\(home)/Library/Logs/TravelTime")

        // 7. Containers (sandbox, if any)
        try? fm.removeItem(atPath: "\(home)/Library/Containers/\(bundleID)")

        // 8. Temporary files (update leftovers)
        let tmpBase = NSTemporaryDirectory()
        if let tmpItems = try? fm.contentsOfDirectory(atPath: tmpBase) {
            for item in tmpItems where item.hasPrefix("tzbar-update-") {
                try? fm.removeItem(atPath: "\(tmpBase)/\(item)")
            }
        }

        // 9. Deregister the login item
        if isBundled {
            try? SMAppService.mainApp.unregister()
        }

        // 10. Delete the app bundle (admin rights)
        //     Also kill Dock to clear Launchpad tile cache
        let appPath = Bundle.main.bundlePath
        let script = """
            do shell script "rm -rf " & quoted form of "\(appPath)" & " && killall Dock" with administrator privileges
            """
        Task {
            do {
                try await PrivilegedRunner.run(script: script)
                // App bundle deleted; quit so the process exits cleanly.
                // isUninstalling is not reset here because the app terminates immediately.
                NSApp.terminate(nil)
            } catch {
                isUninstalling = false
                NSAlert(error: error).runModal()
            }
        }
    }
}

// MARK: - Card container

struct SettingsCard<Content: View>: View {
    var title: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.primary.opacity(0.035))
        )
    }
}

// MARK: - Theme picker helpers

func themeDescription(_ theme: Theme) -> String {
    switch theme {
    case .minimal: return "White, hairline rows, compact"
    case .glass: return "Frosted cards, generous spacing"
    case .midnight: return "Dark with cyan accent"
    case .editorial: return "Serif type, lots of whitespace"
    }
}

struct ThemeSwatch: View {
    let theme: Theme

    /// Show the real current time (via the cached formatter) instead of a
    /// hardcoded "01:42" placeholder.
    private var timeText: String {
        TimeZoneStore.cachedFormatter(format: "HH:mm").string(from: Date())
    }

    var body: some View {
        ZStack {
            // Background surface per theme
            RoundedRectangle(cornerRadius: 6)
                .fill(bgColor)
                .frame(width: 44, height: 44)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(borderColor, lineWidth: 0.5)
                )
            // Mini "dial" ring (matches real panel's accent ring)
            Circle()
                .stroke(accentColor, lineWidth: 2)
                .frame(width: 30, height: 30)
            // Mini time text in theme's typography
            Text(timeText)
                .font(.system(size: 11, weight: .semibold, design: previewDesign))
                .monospacedDigit()
                .foregroundColor(textColor)
        }
    }

    private var previewDesign: Font.Design {
        // Editorial is the only theme that uses serif for the time display.
        theme == .editorial ? .serif : .rounded
    }

    private var bgColor: Color {
        switch theme {
        case .minimal: return Color(hex: "#FFFFFF")
        case .glass: return Color(hex: "#F5F7FA")
        case .midnight: return Color(hex: "#1C1C1E")
        case .editorial: return Color(hex: "#FAFAF8")
        }
    }

    private var borderColor: Color {
        switch theme {
        case .minimal: return Color(hex: "#E5E5EA")
        case .glass: return Color(hex: "#E0E6ED")
        case .midnight: return Color(hex: "#3A3A3C")
        case .editorial: return Color(hex: "#E2E2DC")
        }
    }

    private var textColor: Color {
        switch theme {
        case .midnight: return Color(hex: "#F5F5F7")
        default: return Color(hex: "#1D1D1F")
        }
    }

    private var accentColor: Color {
        switch theme {
        case .minimal, .glass: return Color(hex: "#0A84FF")
        case .midnight: return Color(hex: "#64D2FF")
        case .editorial: return Color(hex: "#C41E3A")
        }
    }
}
