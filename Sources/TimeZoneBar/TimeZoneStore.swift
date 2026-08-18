import SwiftUI
import Combine

struct ZoneEntry: Identifiable, Codable, Hashable {
    var id: String      // IANA identifier, e.g. Asia/Shanghai
    var label: String   // Display name, e.g. Beijing
    var region: String  // Country or region, e.g. China
    var color: String   // Hex accent color
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
}

@MainActor
final class TimeZoneStore: ObservableObject {
    @Published var zones: [ZoneEntry] {
        didSet {
            save()              // persist changes (add/remove/replace)
            onZonesChanged()    // notify AppDelegate to resize the window
        }
    }
    @Published var now = Date()
    @Published var currentZoneIdentifier: String
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
        didSet { defaults.set(theme.rawValue, forKey: Self.themeKey) }
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
    }

    /// Injected by AppDelegate: called whenever the zone list changes, so the
    /// window can auto-resize to fit the new number of rows.
    var onZonesChanged: () -> Void = {}

    /// Window control callbacks — injected by AppDelegate. Used by the
    /// custom-drawn title bar (traffic lights) in MenuPanelView, since the
    /// borderless NSPanel has no system window chrome.
    var closeWindow: () -> Void = {}
    var minimizeWindow: () -> Void = {}
    var zoomWindow: () -> Void = {}

    private let defaults = UserDefaults.standard
    private static let zonesKey = "zones.v1"
    private static let currentZoneKey = "currentZone.v1"
    private static let showDateKey = "pref.showDate"
    private static let use24HourKey = "pref.use24Hour"
    private static let themeKey = "pref.theme"
    private var autoTimezoneMonitor: AnyCancellable?

    /// Path to the user-selected avatar image in Application Support, or nil
    /// to use the bundled default. Reloaded on demand (Refresh) or when
    /// the user picks a new image (Choose avatar callback).
    @Published var avatarPath: String?

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

    static let defaultZones: [ZoneEntry] = [
        ZoneEntry(id: "Asia/Shanghai", label: "Beijing", region: "China", color: "#007AFF"),
        ZoneEntry(id: "Asia/Bangkok", label: "Bangkok", region: "Thailand", color: "#64D2FF"),
        ZoneEntry(id: "Asia/Jakarta", label: "Jakarta", region: "Indonesia", color: "#5E5CE6"),
        ZoneEntry(id: "Europe/London", label: "London", region: "United Kingdom", color: "#FF9F0A"),
        ZoneEntry(id: "America/New_York", label: "New York", region: "United States", color: "#30D158"),
        ZoneEntry(id: "Asia/Tokyo", label: "Tokyo", region: "Japan", color: "#BF5AF2")
    ]

    init() {
        // Load custom avatar path if the user previously picked one
        avatarPath = Self.userAvatarURL()?.path
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
        // autoTimezoneEnabled keeps its default false; refreshed asynchronously below (#7)
        refreshAutoTimezoneFlag()
        startAutoTimezoneMonitoring()
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
    /// 2. polls the flag every 30 s so toggling "Set time zone automatically"
    ///    in System Settings hides the banner on its own.
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
                self?.refreshAutoTimezoneFlag()
            }
    }

    @objc private func handleTimeZoneChange(_ note: Notification) {
        refreshAutoTimezoneFlag()
    }

    // MARK: - Display helpers

    var menuBarText: String {
        let time = timeString(for: currentZoneIdentifier)
        let offset = Self.offsetString(for: currentZoneIdentifier)
        if showDateInMenuBar {
            let f = DateFormatter()
            f.dateFormat = "M/d"
            return "\(f.string(from: now)) \(time) \(offset)"
        }
        return "\(time) \(offset)"
    }

    func timeString(for identifier: String) -> String {
        guard let tz = TimeZone(identifier: identifier) else { return "--:--" }
        let f = DateFormatter()
        f.dateFormat = use24Hour ? "HH:mm" : "h:mm a"
        f.timeZone = tz
        return f.string(from: now)
    }

    func timeString(for zone: ZoneEntry) -> String {
        timeString(for: zone.id)
    }

    /// Whether it is daytime there (calculated from sun position)
    func isDaytime(in identifier: String) -> Bool {
        guard let tz = TimeZone(identifier: identifier) else { return true }
        
        // Get approximate latitude/longitude for the time zone
        // This is a simplified mapping for common time zones
        let coordinates = Self.approximateCoordinates(for: identifier)
        
        // Calculate sun position
        let isDay = Self.isSunUp(latitude: coordinates.lat, longitude: coordinates.lon, date: now, timeZone: tz)
        
        return isDay
    }
    
    /// Approximate coordinates for common time zones
    private static func approximateCoordinates(for identifier: String) -> (lat: Double, lon: Double) {
        switch identifier {
        case "Asia/Shanghai": return (31.2, 121.5)      // Shanghai
        case "Asia/Bangkok": return (13.8, 100.5)        // Bangkok
        case "Asia/Jakarta": return (-6.2, 106.8)        // Jakarta
        case "Europe/London": return (51.5, -0.1)        // London
        case "America/New_York": return (40.7, -74.0)    // New York
        case "Asia/Tokyo": return (35.7, 139.7)          // Tokyo
        default:
            // Extract approximate longitude from time zone offset
            let offset = TimeZone(identifier: identifier)?.secondsFromGMT() ?? 0
            let lon = Double(offset) / 3600.0 * 15.0
            return (0.0, lon)  // Default to equator
        }
    }
    
    /// Calculate if sun is up at the given location and time
    /// Uses a simplified solar position algorithm
    private static func isSunUp(latitude: Double, longitude: Double, date: Date, timeZone: TimeZone) -> Bool {
        // Convert to UTC
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(abbreviation: "UTC")!
        
        let year = cal.component(.year, from: date)
        let month = cal.component(.month, from: date)
        let day = cal.component(.day, from: date)
        let hour = cal.component(.hour, from: date)
        let minute = cal.component(.minute, from: date)
        
        // Calculate day of year
        var dayOfYear = 0
        let daysInMonth = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        for i in 0..<(month - 1) {
            dayOfYear += daysInMonth[i]
        }
        dayOfYear += day
        if month > 2 && year % 4 == 0 && (year % 100 != 0 || year % 400 == 0) {
            dayOfYear += 1
        }
        
        // Solar declination (simplified)
        let declination = -23.44 * cos((2.0 * .pi / 365.0) * Double(dayOfYear + 10))
        
        // Hour angle
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

    // MARK: - Actions

    func switchTo(_ zone: ZoneEntry) {
        guard !isSwitching else { return }
        isSwitching = true
        lastError = nil
        let id = zone.id
        Task {
            do {
                // Timeout: 15 seconds max (waiting for admin authorization)
                try await withThrowingTaskGroup(of: Void.self) { group in
                    group.addTask {
                        try await SystemZoneSwitcher.switchTimeZone(to: id)
                    }
                    group.addTask {
                        try await Task.sleep(nanoseconds: 15_000_000_000)
                        throw ZoneSwitchError.adminRejected("Timed out waiting for authorization")
                    }
                    defer { group.cancelAll() }
                    try await group.next()!
                }
                currentZoneIdentifier = id
                defaults.set(id, forKey: Self.currentZoneKey)
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
        if let entry = zones.first(where: { $0.id == d.timezone }) {
            switchTo(entry)
        } else {
            let entry = ZoneEntry(id: d.timezone,
                                  label: d.city.isEmpty ? d.timezone : d.city,
                                  region: d.country,
                                  color: "#007AFF")
            zones.append(entry)
            save()
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

    /// Persists a current-zone change without running the privileged switcher
    /// (used when the current row is replaced in-place).
    func setCurrentZone(_ id: String) {
        currentZoneIdentifier = id
        defaults.set(id, forKey: Self.currentZoneKey)
    }

    /// #7: Reads the "Set time zone automatically" flag from /Library/Preferences/com.apple.timezone.auto (async version)
    private static func readAutoTimezoneFlagAsync() async -> Bool {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .background).async {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
                p.arguments = ["read", "/Library/Preferences/com.apple.timezone.auto"]
                let pipe = Pipe()
                p.standardOutput = pipe
                p.standardError = Pipe()
                do { try p.run() } catch { 
                    continuation.resume(returning: false)
                    return 
                }
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                let out = String(data: data, encoding: .utf8) ?? ""
                continuation.resume(returning: out.contains("Active = 1"))
            }
        }
    }

    /// Synchronous version kept for backward compatibility (used after switchTo)
    private static func readAutoTimezoneFlag() -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        p.arguments = ["read", "/Library/Preferences/com.apple.timezone.auto"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        do { try p.run() } catch { return false }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let out = String(data: data, encoding: .utf8) ?? ""
        return out.contains("Active = 1")
    }
}
