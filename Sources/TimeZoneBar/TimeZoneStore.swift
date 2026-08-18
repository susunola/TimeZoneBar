import SwiftUI
import Combine
import AppKit   // NSImage (avatar caching)

/// One row in the zone list.
///
/// - `id`   is the IANA identifier (e.g. `Europe/Berlin`) and is **NOT unique** —
///          Berlin and Frankfurt legitimately share `Europe/Berlin`.
/// - `uuid` is a unique identity used by SwiftUI `ForEach` and for
///          delete/replace targeting, so duplicate IANA ids never collide.
struct ZoneEntry: Codable, Hashable {
    var id: String      // IANA identifier (NOT unique!)
    var uuid: UUID      // unique identity for UI (ForEach id, delete/replace)
    var label: String   // Display name, e.g. Beijing
    var region: String  // Country or region, e.g. China
    var color: String   // Hex accent color

    init(id: String, label: String, region: String, color: String, uuid: UUID = UUID()) {
        self.id = id
        self.uuid = uuid
        self.label = label
        self.region = region
        self.color = color
    }

    enum CodingKeys: String, CodingKey {
        case id, uuid, label, region, color
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        // Older persisted payloads predate the uuid field — mint one on decode.
        // It gets persisted on the next save, so each entry only ever needs a
        // synthetic uuid once.
        uuid = (try? c.decode(UUID.self, forKey: .uuid)) ?? UUID()
        label = try c.decode(String.self, forKey: .label)
        region = try c.decode(String.self, forKey: .region)
        color = try c.decode(String.self, forKey: .color)
    }
}

struct DetectedZone: Equatable {
    var timezone: String
    var city: String
    var country: String
}

// MARK: - Theme

enum Theme: String, CaseIterable, Identifiable {
    case minimal
    case glass
    case midnight
    case editorial

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .minimal: return "Minimal"
        case .glass: return "Glass"
        case .midnight: return "Midnight"
        case .editorial: return "Editorial"
        }
    }

    /// Row height in points — single source of truth for both the palette and
    /// the auto-resizing window (AppDelegate.updatePanelHeight).
    var rowHeight: CGFloat {
        switch self {
        case .minimal: return 52
        case .glass: return 82
        case .midnight: return 52
        case .editorial: return 66
        }
    }
}

@MainActor
final class TimeZoneStore: ObservableObject {
    @Published var zones: [ZoneEntry] {
        didSet {
            sanitizeCurrentZone()
            save()              // persist changes (add/remove/replace)
            onZonesChanged()    // notify AppDelegate to resize the window
        }
    }
    @Published var now = Date()
    @Published var currentZoneIdentifier: String
    /// Which row is highlighted as "current". Tracked by uuid so that two rows
    /// sharing an IANA id (Berlin + Frankfurt) never both highlight.
    @Published var currentZoneUUID: UUID?
    @Published var autoTimezoneEnabled = false
    @Published var isSwitching = false
    @Published var lastError: String?
    @Published var detected: DetectedZone?
    @Published var isDetecting = false

    // Persisted display preferences
    @Published var showDateInMenuBar: Bool {
        didSet { defaults.set(showDateInMenuBar, forKey: Self.showDateKey) }
    }
    @Published var use24Hour: Bool {
        didSet { defaults.set(use24Hour, forKey: Self.use24HourKey) }
    }
    @Published var theme: Theme {
        didSet {
            defaults.set(theme.rawValue, forKey: Self.themeKey)
            onThemeChanged()    // window height depends on the theme's row height
        }
    }

    /// Injected by AppDelegate: opens the settings window
    var openSettings: () -> Void = {}

    /// Injected by AppDelegate: shows an open panel for picking a custom avatar image.
    /// The picked file is copied into Application Support/TravelTime/avatar.jpg and
    /// `avatarPath` is reloaded so the AvatarView updates.
    var chooseAvatar: () -> Void = {}

    /// Re-reads the user avatar from disk and republishes. Call after the
    /// choose-avatar callback has written a new file.
    func reloadAvatar() {
        avatarPath = Self.userAvatarURL()?.path
        avatarImage = Self.loadAvatarImage()
    }

    /// Injected by AppDelegate: called whenever the zone list changes, so the
    /// window can auto-resize to fit the new number of rows.
    var onZonesChanged: () -> Void = {}

    /// Injected by AppDelegate: called when the theme changes so the window can
    /// recompute its height (row height differs per theme).
    var onThemeChanged: () -> Void = {}

    /// Whether the main panel is currently on screen. Gates the 30 s
    /// auto-timezone poll so a background app does not fork a process
    /// every half minute while unused.
    private var isPanelVisible = false

    func setPanelVisible(_ visible: Bool) {
        isPanelVisible = visible
    }

    private let defaults: UserDefaults
    private let switcher: any ZoneSwitching
    private static let zonesKey = "zones.v1"
    private static let currentZoneKey = "currentZone.v1"
    private static let currentZoneUUIDKey = "currentZoneUUID.v1"
    private static let showDateKey = "pref.showDate"
    private static let use24HourKey = "pref.use24Hour"
    private static let themeKey = "pref.theme"
    private var autoTimezoneMonitor: AnyCancellable?

    /// Path to the user-selected avatar image in Application Support, or nil
    /// to use the bundled default. Reloaded on demand (Refresh) or when
    /// the user picks a new image (Choose avatar callback).
    @Published var avatarPath: String?

    /// Decoded avatar image, loaded once (never re-decoded on every redraw).
    @Published var avatarImage: NSImage?

    /// Path to the user-picked avatar saved on disk (Application Support).
    /// Returns nil if the user has not picked one.
    static func userAvatarURL() -> URL? {
        guard let support = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else { return nil }
        let dir = support.appendingPathComponent("TravelTime", isDirectory: true)
        let url = dir.appendingPathComponent("avatar.jpg")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// User-picked avatar first, bundled fallback second. NSImage decodes from
    /// disk — keep the result around instead of re-decoding every frame.
    private static func loadAvatarImage() -> NSImage? {
        if let p = userAvatarURL()?.path, let img = NSImage(contentsOfFile: p) {
            return img
        }
        if let url = Bundle.main.url(forResource: "avatar", withExtension: "jpg"),
           let img = NSImage(contentsOf: url) {
            return img
        }
        return nil
    }

    static let defaultZones: [ZoneEntry] = [
        ZoneEntry(id: "Asia/Shanghai", label: "Beijing", region: "China", color: "#007AFF"),
        ZoneEntry(id: "Asia/Bangkok", label: "Bangkok", region: "Thailand", color: "#64D2FF"),
        ZoneEntry(id: "Asia/Jakarta", label: "Jakarta", region: "Indonesia", color: "#5E5CE6"),
        ZoneEntry(id: "Europe/London", label: "London", region: "United Kingdom", color: "#FF9F0A"),
        ZoneEntry(id: "America/New_York", label: "New York", region: "United States", color: "#30D158"),
        ZoneEntry(id: "Asia/Tokyo", label: "Tokyo", region: "Japan", color: "#BF5AF2")
    ]

    /// Accent colors cycled for user-added zones so the list doesn't turn all blue.
    static let zonePalette = ["#007AFF", "#64D2FF", "#5E5CE6", "#FF9F0A", "#30D158", "#BF5AF2", "#FF453A", "#FFD60A"]

    /// Next accent color for a newly added zone.
    func nextZoneColor() -> String {
        Self.zonePalette[zones.count % Self.zonePalette.count]
    }

    init(defaults: UserDefaults = .standard,
         switcher: any ZoneSwitching = SystemZoneSwitcher.shared) {
        self.defaults = defaults
        self.switcher = switcher
        // Load custom avatar path if the user previously picked one
        avatarPath = Self.userAvatarURL()?.path
        avatarImage = Self.loadAvatarImage()
        // Only fall back to defaults when the key has NEVER been written.
        // An intentionally empty array (user deleted every zone) must survive
        // restarts — checking `object(forKey:) == nil` distinguishes the two.
        if defaults.object(forKey: Self.zonesKey) != nil,
           let data = defaults.data(forKey: Self.zonesKey),
           let saved = try? JSONDecoder().decode([ZoneEntry].self, from: data) {
            zones = saved
        } else {
            zones = Self.defaultZones
        }
        // Default to Beijing time if the user has not explicitly chosen another zone yet.
        // This makes the app behave correctly out-of-the-box regardless of the
        // host system's timezone (which can be Bangkok or anything else).
        if let savedZone = defaults.string(forKey: Self.currentZoneKey),
           TimeZone(identifier: savedZone) != nil {
            currentZoneIdentifier = savedZone
        } else {
            currentZoneIdentifier = "Asia/Shanghai"
        }
        showDateInMenuBar = defaults.object(forKey: Self.showDateKey) as? Bool ?? false
        use24Hour = defaults.object(forKey: Self.use24HourKey) as? Bool ?? true
        theme = Theme(rawValue: defaults.string(forKey: Self.themeKey) ?? "") ?? .minimal
        // Restore the highlighted row. Prefer the persisted uuid (so a
        // Frankfurt row stays highlighted after restart even though Berlin
        // shares its IANA id); fall back to the first row matching the id.
        // Written with plain loops (no closures) because this runs during
        // init, before all stored properties are initialized.
        var matchedUUID: UUID?
        if let s = defaults.string(forKey: Self.currentZoneUUIDKey),
           let u = UUID(uuidString: s),
           zones.contains(where: { $0.uuid == u }) {
            matchedUUID = u
        } else {
            for z in zones where z.id == currentZoneIdentifier {
                matchedUUID = z.uuid
                break
            }
        }
        currentZoneUUID = matchedUUID
        // autoTimezoneEnabled keeps its default false; refreshed asynchronously below
        refreshAutoTimezoneFlag()
        startAutoTimezoneMonitoring()
    }

    /// Drops the current-row pointer when its row was deleted / replaced by
    /// Restore Defaults. Falls back to the first row with the same IANA id so
    /// the highlight (and the Remove-disabled state) stays sane — e.g. after
    /// Restore Defaults the Beijing row is highlighted again. The fallback is
    /// persisted so a relaunch doesn't re-read a stale uuid.
    private func sanitizeCurrentZone() {
        guard let u = currentZoneUUID, !zones.contains(where: { $0.uuid == u }) else { return }
        let fallback = zones.first { $0.id == currentZoneIdentifier }?.uuid
        currentZoneUUID = fallback
        if let fallback {
            defaults.set(fallback.uuidString, forKey: Self.currentZoneUUIDKey)
        } else {
            defaults.removeObject(forKey: Self.currentZoneUUIDKey)
        }
    }

    // MARK: - Auto timezone monitoring

    /// Re-reads the macOS "Set time zone automatically" flag and publishes it.
    /// Safe to call repeatedly — cheap, non-blocking (background process read).
    func refreshAutoTimezoneFlag() {
        Task { [weak self] in
            let flag = await Self.readAutoTimezoneFlagAsync()
            await MainActor.run {
                guard let self else { return }
                if self.autoTimezoneEnabled != flag {
                    self.autoTimezoneEnabled = flag
                }
            }
        }
    }

    /// Keeps the warning banner in sync with System Settings:
    /// 1. refreshes when the system time zone changes, and
    /// 2. polls the flag every 30 s while the panel is visible, so toggling
    ///    "Set time zone automatically" in System Settings hides the banner
    ///    on its own.
    private func startAutoTimezoneMonitoring() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleTimeZoneChange(_:)),
            name: .NSSystemTimeZoneDidChange,
            object: nil
        )
        autoTimezoneMonitor = Timer.publish(every: 30, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self, self.isPanelVisible else { return }
                self.refreshAutoTimezoneFlag()
            }
    }

    @objc private func handleTimeZoneChange(_ note: Notification) {
        refreshAutoTimezoneFlag()
    }

    // MARK: - Display helpers

    /// Cached DateFormatters — constructing one is expensive and the panel
    /// redraws every minute, so reuse per (format, timezone) pair. Bounded by
    /// (number of zones × 2 formats), so it can never grow unbounded. This is
    /// mutable static state: only ever touch it from the MainActor (both the
    /// store and the SwiftUI views are MainActor-isolated).
    private static var formatterCache: [String: DateFormatter] = [:]

    static func cachedFormatter(format: String, timeZone: TimeZone? = nil) -> DateFormatter {
        let key = "\(format)|\(timeZone?.identifier ?? "local")"
        if let f = formatterCache[key] { return f }
        let f = DateFormatter()
        f.dateFormat = format
        f.timeZone = timeZone ?? .current
        formatterCache[key] = f
        return f
    }

    var menuBarText: String {
        let time = timeString(for: currentZoneIdentifier)
        let offset = Self.offsetString(for: currentZoneIdentifier)
        if showDateInMenuBar {
            // Date is formatted in the DISPLAYED zone, matching the time.
            let date = Self.cachedFormatter(
                format: "M/d",
                timeZone: TimeZone(identifier: currentZoneIdentifier)
            ).string(from: now)
            return "\(date) \(time) \(offset)"
        }
        return "\(time) \(offset)"
    }

    func timeString(for identifier: String) -> String {
        guard let tz = TimeZone(identifier: identifier) else { return "--:--" }
        let format = use24Hour ? "HH:mm" : "h:mm a"
        return Self.cachedFormatter(format: format, timeZone: tz).string(from: now)
    }

    func timeString(for zone: ZoneEntry) -> String {
        timeString(for: zone.id)
    }

    /// Whether it is daytime there (calculated from sun position)
    func isDaytime(in identifier: String) -> Bool {
        guard let tz = TimeZone(identifier: identifier) else { return true }

        // Get approximate latitude/longitude for the time zone
        let coordinates = Self.approximateCoordinates(for: identifier)

        // Calculate sun position
        return Self.isSunUp(latitude: coordinates.lat, longitude: coordinates.lon, date: now, timeZone: tz)
    }

    /// Approximate coordinates for the common zones. Covers every entry in
    /// SettingsView.commonZones so the day/night badge is right for any zone
    /// the user can add.
    private static let zoneCoordinates: [String: (lat: Double, lon: Double)] = [
        "Asia/Shanghai": (31.2, 121.5),
        "Asia/Bangkok": (13.8, 100.5),
        "Asia/Jakarta": (-6.2, 106.8),
        "Asia/Hong_Kong": (22.3, 114.2),
        "Asia/Taipei": (25.0, 121.5),
        "Asia/Tokyo": (35.7, 139.7),
        "Asia/Seoul": (37.6, 127.0),
        "Asia/Singapore": (1.35, 103.8),
        "Asia/Dubai": (25.2, 55.3),
        "Asia/Kolkata": (28.6, 77.2),   // New Delhi — the label used in commonZones
        "Australia/Sydney": (-33.9, 151.2),
        "Pacific/Auckland": (-36.8, 174.8),
        "Europe/London": (51.5, -0.1),
        "Europe/Paris": (48.9, 2.35),
        "Europe/Berlin": (52.5, 13.4),
        "Europe/Madrid": (40.4, -3.7),
        "Europe/Rome": (41.9, 12.5),
        "Europe/Amsterdam": (52.4, 4.9),
        "America/New_York": (40.7, -74.0),
        "America/Los_Angeles": (34.05, -118.24),
        "America/Chicago": (41.9, -87.6),
        "America/Sao_Paulo": (-23.55, -46.63),
        "UTC": (0, 0)
    ]

    private static func approximateCoordinates(for identifier: String) -> (lat: Double, lon: Double) {
        if let c = zoneCoordinates[identifier] { return c }
        // Fallback for exotic zones: derive longitude from the UTC offset,
        // keep latitude at the equator. Only affects the day/night badge.
        let offset = TimeZone(identifier: identifier)?.secondsFromGMT() ?? 0
        var lon = Double(offset) / 3600.0 * 15.0
        lon = max(-180, min(180, lon))
        return (0.0, lon)
    }

    /// Calculate if sun is up at the given location and time
    /// Uses a simplified solar position algorithm
    private static func isSunUp(latitude: Double, longitude: Double, date: Date, timeZone: TimeZone) -> Bool {
        // The clock reading must be the zone's LOCAL time: taking the UTC hour
        // and then subtracting the offset again double-counts the offset and
        // shifts the day/night boundary by the full zone difference (e.g. Tokyo
        // 13:00 was judged "night").
        var local = Calendar(identifier: .gregorian)
        local.timeZone = timeZone
        let hour = local.component(.hour, from: date)
        let minute = local.component(.minute, from: date)

        // Day of year (handles leap years correctly via the calendar)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = .gmt
        let dayOfYear = utc.ordinality(of: .day, in: .year, for: date) ?? 1

        // Solar declination (simplified)
        let declination = -23.44 * cos((2.0 * .pi / 365.0) * Double(dayOfYear + 10))

        // Hour angle. The local clock hour already includes the zone offset, so
        // express it back in UTC and then correct for longitude.
        let fractionalHour = Double(hour) + Double(minute) / 60.0
        let utcHour = fractionalHour - Double(timeZone.secondsFromGMT()) / 3600.0
        let solarTime = utcHour + longitude / 15.0
        let hourAngle = (solarTime - 12.0) * 15.0

        // Solar elevation
        let latRad = latitude * .pi / 180.0
        let decRad = declination * .pi / 180.0
        let haRad = hourAngle * .pi / 180.0

        let sinElevation = sin(latRad) * sin(decRad) + cos(latRad) * cos(decRad) * cos(haRad)
        let elevation = asin(sinElevation) * 180.0 / .pi

        // Sun is up if elevation > -0.83 degrees (accounting for atmospheric refraction)
        return elevation > -0.83
    }

    /// Whether the zone currently observes daylight saving time
    func isDST(in identifier: String) -> Bool {
        guard let tz = TimeZone(identifier: identifier) else { return false }
        return tz.isDaylightSavingTime(for: now)
    }

    /// Hour of the day (0-23) in the given zone at the given instant. Pure so
    /// the quote-of-the-hour rotation can be unit-tested.
    static func hourOfDay(in identifier: String, at date: Date) -> Int {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: identifier) ?? .current
        return cal.component(.hour, from: date)
    }

    static func offsetString(for identifier: String) -> String {
        guard let tz = TimeZone(identifier: identifier) else { return "" }
        let total = tz.secondsFromGMT()
        let sign = total < 0 ? "-" : "+"
        let absTotal = abs(total)
        let hours = absTotal / 3600
        let minutes = (absTotal % 3600) / 60
        if minutes == 0 { return "\(sign)\(hours)" }
        return String(format: "%@%d:%02d", sign, hours, minutes)
    }

    /// Day offset vs the system zone: 0 same day, -1 yesterday, +1 tomorrow
    func dayDifference(for zone: ZoneEntry) -> Int {
        guard let tz = TimeZone(identifier: zone.id) else { return 0 }
        var here = Calendar(identifier: .gregorian)
        here.timeZone = TimeZone.current
        let hereDay = here.startOfDay(for: now)
        var there = Calendar(identifier: .gregorian)
        there.timeZone = tz
        let thereDay = there.startOfDay(for: now)
        return there.dateComponents([.day], from: hereDay, to: thereDay).day ?? 0
    }

    /// Human label for a day offset (-1 yesterday, 0 today, +1 tomorrow).
    /// Pure function so every theme renders the same calendar truth.
    static func dayLabel(for dayDifference: Int) -> String {
        switch dayDifference {
        case -1: return "Yesterday"
        case 1: return "Tomorrow"
        default: return "Today"
        }
    }

    // MARK: - Actions

    /// Switches the SYSTEM time zone (admin prompt) and marks the row as current.
    func switchTo(_ zone: ZoneEntry) {
        guard !isSwitching else { return }
        // Validate before anything touches the privileged path — a bad IANA id
        // must never reach the shell.
        guard TimeZone(identifier: zone.id) != nil else {
            lastError = "Invalid time zone: \(zone.id)"
            return
        }
        isSwitching = true
        lastError = nil
        let id = zone.id
        let uuid = zone.uuid
        Task {
            do {
                // PrivilegedRunner enforces its own 15 s timeout and kills the
                // osascript child if the user ignores the authorization dialog.
                try await switcher.switchTimeZone(to: id)
                currentZoneIdentifier = id
                currentZoneUUID = uuid
                defaults.set(id, forKey: Self.currentZoneKey)
                defaults.set(uuid.uuidString, forKey: Self.currentZoneUUIDKey)
                let flag = await Self.readAutoTimezoneFlagAsync()
                autoTimezoneEnabled = flag
            } catch let error as ZoneSwitchError {
                // User canceling the authorization dialog is a deliberate "no",
                // not an error to surface — keep the panel quiet.
                if case .userCanceled = error { }
                else { lastError = error.localizedDescription }
            } catch {
                lastError = error.localizedDescription
            }
            isSwitching = false
        }
    }

    func detectLocation() {
        guard !isDetecting else { return }
        isDetecting = true
        lastError = nil
        detected = nil
        Task {
            do {
                // Timeout: 10 seconds max for network request
                try await withThrowingTaskGroup(of: DetectedZone.self) { group in
                    group.addTask {
                        try await LocationDetector.detect()
                    }
                    group.addTask {
                        try await Task.sleep(nanoseconds: 10_000_000_000)
                        throw DetectionError.failed
                    }
                    defer { group.cancelAll() }
                    detected = try await group.next()!
                }
            } catch {
                lastError = error.localizedDescription
            }
            isDetecting = false
        }
    }

    func confirmDetectedZone() {
        guard let d = detected else { return }
        // A geo response is untrusted input that flows into a privileged
        // timezone switch — validate it before it can reach that path.
        guard TimeZone(identifier: d.timezone) != nil else {
            lastError = "Detected time zone is not valid: \(d.timezone)"
            return
        }
        if let entry = zones.first(where: { $0.id == d.timezone }) {
            switchTo(entry)
        } else {
            let entry = ZoneEntry(id: d.timezone,
                                  label: d.city.isEmpty ? d.timezone : d.city,
                                  region: d.country,
                                  color: nextZoneColor())
            zones.append(entry)     // didSet persists
            switchTo(entry)
        }
    }

    func save() {
        do {
            let data = try JSONEncoder().encode(zones)
            defaults.set(data, forKey: Self.zonesKey)
        } catch {
            lastError = "Failed to save settings: \(error.localizedDescription)"
        }
    }

    /// Persists a current-zone change without running the privileged switcher.
    /// Used when the current row is replaced in-place — the header follows the
    /// new city, but the OS time zone itself only changes when the user clicks
    /// a row (that path is admin-gated).
    func setCurrentZone(_ id: String, uuid: UUID? = nil) {
        currentZoneIdentifier = id
        defaults.set(id, forKey: Self.currentZoneKey)
        if let uuid {
            currentZoneUUID = uuid
            defaults.set(uuid.uuidString, forKey: Self.currentZoneUUIDKey)
        }
    }

    /// Reads the "Set time zone automatically" flag.
    ///
    /// macOS 26 no longer keeps `/Library/Preferences/com.apple.timezone.auto`
    /// on disk; `defaults read` would return a stale value cached by cfprefsd
    /// (we observed "Active = 1" long after the user turned the switch off).
    /// So we trust the disk file only and **fail closed** (assume OFF) when it
    /// is absent. On macOS 14/15 the file exists and the real value is read.
    private static func readAutoTimezoneFlagAsync() async -> Bool {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .background).async {
                let path = "/Library/Preferences/com.apple.timezone.auto"
                guard FileManager.default.fileExists(atPath: path) else {
                    continuation.resume(returning: false)
                    return
                }
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/bin/plutil")
                p.arguments = ["-extract", "Active", "raw", "-o", "-", path]
                let pipe = Pipe()
                p.standardOutput = pipe
                p.standardError = Pipe()
                do { try p.run() } catch {
                    continuation.resume(returning: false)
                    return
                }
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                let out = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                continuation.resume(returning: out == "1" || out.lowercased() == "true")
            }
        }
    }
}
