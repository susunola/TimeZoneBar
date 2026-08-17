import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @EnvironmentObject var store: TimeZoneStore
    @StateObject private var updater = Updater()
    @State private var addSelection = "Asia/Shanghai"
    @State private var launchAtLogin = false

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
        ("America/New_York", "New York", "United States"),
        ("America/Los_Angeles", "Los Angeles", "United States"),
        ("America/Chicago", "Chicago", "United States"),
        ("America/Sao_Paulo", "São Paulo", "Brazil"),
        ("UTC", "Coordinated Universal Time", "")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("TimeZoneBar Settings")
                .font(.title2)

            if #available(macOS 26, *) {
                Label("macOS 26: if the icon is missing, enable TimeZoneBar under System Settings › Menu Bar › Allow in the Menu Bar",
                      systemImage: "info.circle")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

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
                        }
                    }
            }

            Divider()

            Text("Time Zones")
                .font(.headline)

            HStack(spacing: 8) {
                Picker("Add a time zone", selection: $addSelection) {
                    ForEach(Self.commonZones, id: \.id) { item in
                        Text(item.region.isEmpty ? item.label : "\(item.label) · \(item.region)")
                            .tag(item.id)
                    }
                }
                .labelsHidden()

                Button("Add") {
                    guard !store.zones.contains(where: { $0.id == addSelection }) else { return }
                    let item = Self.commonZones.first { $0.id == addSelection }
                    store.zones.append(ZoneEntry(id: addSelection,
                                                 label: item?.label ?? addSelection,
                                                 region: item?.region ?? "",
                                                 color: "#007AFF"))
                    store.save()
                }
                .disabled(store.zones.contains { $0.id == addSelection })
            }

            ForEach(store.zones) { zone in
                HStack {
                    Circle()
                        .fill(Color(hex: zone.color))
                        .frame(width: 8, height: 8)
                    Text("\(zone.label) (\(zone.id))")
                        .font(.system(size: 13))
                    Spacer()
                    if zone.id == store.currentZoneIdentifier {
                        Text("Current")
                            .font(.system(size: 11))
                            .foregroundColor(.blue)
                    }
                    Button("Remove") {
                        store.zones.removeAll { $0.id == zone.id }
                        store.save()
                    }
                    .disabled(zone.id == store.currentZoneIdentifier)
                }
            }

            Button("Restore Defaults") {
                store.zones = TimeZoneStore.defaultZones
                store.save()
            }

            Divider()
                .padding(.top, 8)

            Text("Display")
                .font(.headline)

            Toggle("Show date in the menu bar", isOn: $store.showDateInMenuBar)

            Picker("Time format", selection: $store.use24Hour) {
                Text("24-hour").tag(true)
                Text("12-hour").tag(false)
            }
            .pickerStyle(.segmented)

            Divider()
                .padding(.top, 8)

            // Software update
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
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.blue.opacity(0.06))
            )

            Divider()
                .padding(.top, 8)

            // Uninstall
            HStack(spacing: 10) {
                Image(systemName: "trash")
                    .font(.system(size: 13))
                    .foregroundColor(.red)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Uninstall TimeZoneBar")
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
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.red.opacity(0.06))
            )
            .confirmationDialog("Uninstall TimeZoneBar?",
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
        .padding(24)
        .frame(width: 460)
        .onAppear {
            if isBundled {
                launchAtLogin = (SMAppService.mainApp.status == .enabled)
            }
        }
    }

    @State private var showUninstallConfirm = false
    @State private var isUninstalling = false

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
            .appendingPathComponent("TimeZoneBar", isDirectory: true) {
            try? fm.removeItem(at: appSupport)
        }

        // 3. Caches
        let cachesDir = fm.urls(for: .cachesDirectory, in: .userDomainMask).first!
        try? fm.removeItem(at: cachesDir.appendingPathComponent(bundleID))
        try? fm.removeItem(at: cachesDir.appendingPathComponent("TimeZoneBar"))

        // 4. Saved Application State (window restore)
        let savedState = "\(home)/Library/Saved Application State/\(bundleID).savedState"
        try? fm.removeItem(atPath: savedState)

        // 5. HTTPStorages (URLSession cookies/cache)
        let httpStorages = "\(home)/Library/HTTPStorages/\(bundleID)"
        try? fm.removeItem(atPath: httpStorages)

        // 6. Logs
        try? fm.removeItem(atPath: "\(home)/Library/Logs/TimeZoneBar")

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
                isUninstalling = false
                NSApp.terminate(nil)
            } catch {
                isUninstalling = false
                NSAlert(error: error).runModal()
            }
        }
    }
}
