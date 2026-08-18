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
        let store = TimeZoneStore()
        // A zone whose id equals the host system zone is always "Today".
        let zone = ZoneEntry(id: TimeZone.current.identifier,
                             label: "Local",
                             region: "",
                             color: "#007AFF")
        XCTAssertEqual(store.dayDifference(for: zone), 0)
    }
}
