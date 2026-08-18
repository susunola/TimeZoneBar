import XCTest
@testable import TravelTime

/// Unit tests for the pure logic in TravelTime.
///
/// The UI layer (SwiftUI views, NSWindow handling) is intentionally not
/// covered here — these tests target the small, deterministic functions that
/// actually carry risk: time formatting, version comparison, checksum parsing
/// and the legacy-data migration path of ZoneEntry.
final class TravelTimeTests: XCTestCase {

    // MARK: - offsetString

    // TimeZoneStore is @MainActor, so its static helpers are MainActor-isolated too.
    @MainActor
    func testOffsetStringWholeHours() {
        XCTAssertEqual(TimeZoneStore.offsetString(for: "Asia/Shanghai"), "+8")
        XCTAssertEqual(TimeZoneStore.offsetString(for: "Asia/Tokyo"), "+9")
        // Fixed-offset IANA zone (DST-free) so the assertion is date-independent.
        XCTAssertEqual(TimeZoneStore.offsetString(for: "Etc/GMT+5"), "-5")
    }

    @MainActor
    func testOffsetStringHalfHours() {
        XCTAssertEqual(TimeZoneStore.offsetString(for: "Asia/Kolkata"), "+5:30")
    }

    @MainActor
    func testOffsetStringInvalidZone() {
        XCTAssertEqual(TimeZoneStore.offsetString(for: "Not/AZone"), "")
    }

    // MARK: - ZoneEntry legacy migration

    func testZoneEntryDecodesLegacyPayloadWithoutUUID() throws {
        // Payloads written before the uuid field existed must decode and mint
        // a stable identity so duplicate IANA ids stay distinct in the UI.
        let json = """
        [{"id":"Europe/Berlin","label":"Berlin","region":"Germany","color":"#FF9F0A"},
         {"id":"Europe/Berlin","label":"Frankfurt","region":"Germany","color":"#FF9F0A"}]
        """.data(using: .utf8)!
        let zones = try JSONDecoder().decode([ZoneEntry].self, from: json)
        XCTAssertEqual(zones.count, 2)
        XCTAssertEqual(zones[0].id, "Europe/Berlin")
        XCTAssertEqual(zones[1].id, "Europe/Berlin")
        // Two rows sharing an IANA id must never share a uuid.
        XCTAssertNotEqual(zones[0].uuid, zones[1].uuid)
    }

    func testZoneEntryRoundTripPersistsUUID() throws {
        let zone = ZoneEntry(id: "Asia/Shanghai", label: "Beijing", region: "China", color: "#007AFF")
        let data = try JSONEncoder().encode([zone])
        let decoded = try JSONDecoder().decode([ZoneEntry].self, from: data)
        XCTAssertEqual(decoded[0].uuid, zone.uuid)
    }

    // MARK: - Version comparison (Updater)

    @MainActor
    func testParseVersion() {
        let updater = Updater()
        XCTAssertEqual(updater.parseVersion("v1.2.3"), [1, 2, 3])
        XCTAssertEqual(updater.parseVersion("1.2"), [1, 2])
        XCTAssertEqual(updater.parseVersion("2.0.0-beta.1"), [2, 0, 0]) // non-numeric parts dropped
        XCTAssertEqual(updater.parseVersion("garbage"), [])
    }

    @MainActor
    func testIsVersionGreater() {
        let updater = Updater()
        XCTAssertTrue(updater.isVersionGreater([2, 0, 0], than: [1, 9, 9]))
        XCTAssertTrue(updater.isVersionGreater([1, 10, 0], than: [1, 9, 9]))
        XCTAssertFalse(updater.isVersionGreater([1, 2, 3], than: [1, 2, 3]))
        XCTAssertFalse(updater.isVersionGreater([1, 2], than: [1, 2, 1])) // shorter = older
        XCTAssertTrue(updater.isVersionGreater([1, 2, 1], than: [1, 2]))
    }

    // MARK: - SHA256 checksum parsing (Updater)

    @MainActor
    func testSHA256FromBody() {
        let updater = Updater()
        let hash = String(repeating: "ab", count: 32) // 64 hex chars
        XCTAssertEqual(updater.sha256FromBody("SHA256: \(hash)"), hash)
        XCTAssertEqual(updater.sha256FromBody("Checksum: \(hash)"), hash)
        XCTAssertEqual(updater.sha256FromBody("v1.0.0\nSHA256: \(hash)\nnotes"), hash)
        XCTAssertNil(updater.sha256FromBody("no checksum here"))
        XCTAssertNil(updater.sha256FromBody("SHA256: short"))
    }

    // MARK: - Day difference

    @MainActor
    func testDayDifferenceSameZoneIsZero() {
        let store = makeStore()
        // A zone whose id equals the host system zone is always "Today".
        let zone = ZoneEntry(id: TimeZone.current.identifier,
                             label: "Local",
                             region: "",
                             color: "#007AFF")
        XCTAssertEqual(store.dayDifference(for: zone), 0)
    }

    // MARK: - Current zone highlight (uuid)

    /// A fresh store backed by an isolated defaults suite, so tests never read
    /// or write the real app preferences.
    @MainActor
    private func makeStore() -> TimeZoneStore {
        let suiteName = "tz.test.\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: suiteName)!
        suite.removePersistentDomain(forName: suiteName)
        return TimeZoneStore(defaults: suite)
    }

    @MainActor
    func testCurrentZoneUUIDRestoredOnLaunch() throws {
        // Two rows share Europe/Berlin. The user highlighted Frankfurt; on a
        // relaunch the highlight must land on Frankfurt, not the first match
        // (Berlin).
        let suiteName = "tz.test.uuid.\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: suiteName)!
        defer { suite.removePersistentDomain(forName: suiteName) }

        let berlin = ZoneEntry(id: "Europe/Berlin", label: "Berlin", region: "Germany", color: "#FF9F0A")
        let frankfurt = ZoneEntry(id: "Europe/Berlin", label: "Frankfurt", region: "Germany", color: "#FF9F0A")
        suite.set(try JSONEncoder().encode([berlin, frankfurt]), forKey: "zones.v1")
        suite.set("Europe/Berlin", forKey: "currentZone.v1")
        suite.set(frankfurt.uuid.uuidString, forKey: "currentZoneUUID.v1")

        let store = TimeZoneStore(defaults: suite)
        XCTAssertEqual(store.currentZoneUUID, frankfurt.uuid)
    }

    @MainActor
    func testDeletingCurrentRowRematchesByID() throws {
        // Restore Defaults / row deletion wipes the highlighted row — the
        // highlight must fall back to another row with the same IANA id rather
        // than vanishing entirely (which also re-enables its Remove button).
        let suiteName = "tz.test.rematch.\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: suiteName)!
        defer { suite.removePersistentDomain(forName: suiteName) }

        let berlin = ZoneEntry(id: "Europe/Berlin", label: "Berlin", region: "Germany", color: "#FF9F0A")
        let frankfurt = ZoneEntry(id: "Europe/Berlin", label: "Frankfurt", region: "Germany", color: "#FF9F0A")
        suite.set(try JSONEncoder().encode([berlin, frankfurt]), forKey: "zones.v1")
        suite.set("Europe/Berlin", forKey: "currentZone.v1")
        suite.set(berlin.uuid.uuidString, forKey: "currentZoneUUID.v1")

        let store = TimeZoneStore(defaults: suite)
        XCTAssertEqual(store.currentZoneUUID, berlin.uuid)

        store.zones.removeAll { $0.uuid == berlin.uuid }
        XCTAssertEqual(store.currentZoneUUID, frankfurt.uuid)
    }

    @MainActor
    func testZonePaletteCycles() {
        let store = makeStore()
        // The palette is longer than the default zone count, so consecutive
        // adds never repeat the same color until it wraps.
        var seen = Set<String>()
        for _ in 0..<TimeZoneStore.zonePalette.count {
            let color = store.nextZoneColor()
            seen.insert(color)
            store.zones.append(ZoneEntry(id: "Test/\(seen.count)",
                                         label: "T\(seen.count)",
                                         region: "",
                                         color: color))
        }
        XCTAssertEqual(seen.count, TimeZoneStore.zonePalette.count)
    }

    // MARK: - Panel auto-height (AppDelegate)

    /// Regression for the launch-size bug: the window stayed at its hardcoded
    /// initial height because updatePanelHeight() was only reachable through
    /// store callbacks assigned after the store had already loaded its zones.
    /// The sizing rule is now a pure function; these pin it down.
    @MainActor
    func testPanelContentHeightScalesWithZoneCount() {
        XCTAssertEqual(AppDelegate.panelContentHeight(zoneCount: 3, theme: .minimal), 540)
        XCTAssertEqual(AppDelegate.panelContentHeight(zoneCount: 12, theme: .minimal), 1008)
        XCTAssertEqual(AppDelegate.panelContentHeight(zoneCount: 3, theme: .midnight), 540)
    }

    @MainActor
    func testPanelContentHeightEditorialUsesMoreChrome() {
        XCTAssertEqual(AppDelegate.panelContentHeight(zoneCount: 3, theme: .editorial), 622)
    }

    @MainActor
    func testPanelContentHeightHasMinimum() {
        // Even a single zone must not collapse below the header+footer floor.
        XCTAssertEqual(AppDelegate.panelContentHeight(zoneCount: 0, theme: .minimal), 460)
        XCTAssertEqual(AppDelegate.panelContentHeight(zoneCount: 1, theme: .minimal), 460)
    }

    // MARK: - App bundle discovery (Updater)

    /// Regression for the update bug: releases up to v1.3.3 extract to
    /// TimeZoneBar.app while the updater hardcoded TravelTime.app, so the
    /// post-unzip guard always failed ("Could not unzip the installer").
    func testAppBundleFindsLegacyName() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tzbar-test-legacy-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: dir.appendingPathComponent("TimeZoneBar.app"),
            withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let found = Updater.appBundle(in: dir)
        XCTAssertEqual(found?.lastPathComponent, "TimeZoneBar.app")
    }

    func testAppBundleFindsCurrentName() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tzbar-test-current-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: dir.appendingPathComponent("TravelTime.app"),
            withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let found = Updater.appBundle(in: dir)
        XCTAssertEqual(found?.lastPathComponent, "TravelTime.app")
    }

    func testAppBundleIgnoresZipAndScratchFiles() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tzbar-test-nobundle-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        // An extracted archive dir still holds the zip and any notes; none of
        // these is an app bundle, so discovery must come up empty.
        try Data("zip".utf8).write(to: dir.appendingPathComponent("TravelTime.app.zip"))
        try Data("notes".utf8).write(to: dir.appendingPathComponent("notes.txt"))

        XCTAssertNil(Updater.appBundle(in: dir))
    }
}
