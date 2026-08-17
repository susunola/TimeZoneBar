import SwiftUI

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

@MainActor
final class TimeZoneStore: ObservableObject {
    @Published var zones: [ZoneEntry]
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

    /// Injected by AppDelegate: opens the settings window
    var openSettings: () -> Void = {}

    private let defaults = UserDefaults.standard
    private static let zonesKey = "zones.v1"
    private static let showDateKey = "pref.showDate"
    private static let use24HourKey = "pref.use24Hour"

    static let defaultZones: [ZoneEntry] = [
        ZoneEntry(id: "Asia/Shanghai", label: "Beijing", region: "China", color: "#007AFF"),
        ZoneEntry(id: "Asia/Bangkok", label: "Bangkok", region: "Thailand", color: "#64D2FF"),
        ZoneEntry(id: "Asia/Jakarta", label: "Jakarta", region: "Indonesia", color: "#5E5CE6"),
        ZoneEntry(id: "Europe/London", label: "London", region: "United Kingdom", color: "#FF9F0A"),
        ZoneEntry(id: "America/New_York", label: "New York", region: "United States", color: "#30D158"),
        ZoneEntry(id: "Asia/Tokyo", label: "Tokyo", region: "Japan", color: "#BF5AF2")
    ]

    init() {
        if let data = defaults.data(forKey: Self.zonesKey),
           let saved = try? JSONDecoder().decode([ZoneEntry].self, from: data),
           !saved.isEmpty {
            zones = saved
        } else {
            zones = Self.defaultZones
        }
        currentZoneIdentifier = TimeZone.current.identifier
        autoTimezoneEnabled = Self.readAutoTimezoneFlag()
        showDateInMenuBar = defaults.object(forKey: Self.showDateKey) as? Bool ?? false
        use24Hour = defaults.object(forKey: Self.use24HourKey) as? Bool ?? true
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

    /// Whether it is daytime there (06:00-18:00, simplified)
    func isDaytime(in identifier: String) -> Bool {
        guard let tz = TimeZone(identifier: identifier) else { return true }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        let hour = cal.component(.hour, from: now)
        return hour >= 6 && hour < 18
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
                try await SystemZoneSwitcher.switchTimeZone(to: id)
                currentZoneIdentifier = id
                autoTimezoneEnabled = Self.readAutoTimezoneFlag()
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
                detected = try await LocationDetector.detect()
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
        if let data = try? JSONEncoder().encode(zones) {
            defaults.set(data, forKey: Self.zonesKey)
        }
    }

    /// Reads the "Set time zone automatically" flag from /Library/Preferences/com.apple.timezone.auto
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
