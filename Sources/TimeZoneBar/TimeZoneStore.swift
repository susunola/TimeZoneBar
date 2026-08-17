import SwiftUI

struct ZoneEntry: Identifiable, Codable, Hashable {
    var id: String      // IANA 时区标识，如 Asia/Shanghai
    var label: String   // 显示名，如 北京
    var region: String  // 国家/地区，如 中国
    var color: String   // 十六进制标记色
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

    /// 由 AppDelegate 注入的回调：打开设置窗口
    var openSettings: () -> Void = {}

    private let defaults = UserDefaults.standard
    private static let zonesKey = "zones.v1"

    static let defaultZones: [ZoneEntry] = [
        ZoneEntry(id: "Asia/Shanghai", label: "北京", region: "中国", color: "#007AFF"),
        ZoneEntry(id: "Asia/Bangkok", label: "曼谷", region: "泰国", color: "#64D2FF"),
        ZoneEntry(id: "Asia/Jakarta", label: "雅加达", region: "印度尼西亚", color: "#5E5CE6"),
        ZoneEntry(id: "Europe/London", label: "伦敦", region: "英国", color: "#FF9F0A"),
        ZoneEntry(id: "America/New_York", label: "纽约", region: "美国", color: "#30D158"),
        ZoneEntry(id: "Asia/Tokyo", label: "东京", region: "日本", color: "#BF5AF2")
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
    }

    // MARK: - 显示辅助

    var menuBarText: String {
        "\(timeString(for: currentZoneIdentifier)) \(Self.offsetString(for: currentZoneIdentifier))"
    }

    func timeString(for identifier: String) -> String {
        guard let tz = TimeZone(identifier: identifier) else { return "--:--" }
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        f.timeZone = tz
        return f.string(from: now)
    }

    func timeString(for zone: ZoneEntry) -> String {
        timeString(for: zone.id)
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

    /// 相对当前系统时区的日差：0 同一天，-1 昨天，+1 明天
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

    // MARK: - 动作

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

    /// 读取「自动设置时区（基于定位）」开关：/Library/Preferences/com.apple.timezone.auto
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
