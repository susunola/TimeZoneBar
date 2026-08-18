import SwiftUI
import AppKit

// MARK: - Theme palette

struct ThemePalette {
    let window: Color          // panel background
    let surface: Color         // row / card surface
    let surfaceAlt: Color      // alternate row surface (midnight: dimmed row)
    let textPrimary: Color
    let textSecondary: Color
    let textTertiary: Color
    let accent: Color
    let hairline: Color
    let rowRadius: CGFloat
    let headerTimeSize: CGFloat
    let quoteIsSerif: Bool
    let quoteHasMarks: Bool
    let useCards: Bool         // rows as cards (glass) vs flat rows
    let useAccentBars: Bool    // 4px accent bar on rows (minimal / midnight)
    let detectIsSolid: Bool    // solid accent detect button (glass)
    let panelRadius: CGFloat
    let rowHeight: CGFloat     // used for auto window height

    static func palette(for theme: Theme) -> ThemePalette {
        switch theme {
        case .minimal:
            return ThemePalette(window: Color(hex: "#FFFFFF"),
                                surface: Color(hex: "#FFFFFF"),
                                surfaceAlt: Color(hex: "#F0F6FF"),
                                textPrimary: Color(hex: "#1D1D1F"),
                                textSecondary: Color(hex: "#86868B"),
                                textTertiary: Color(hex: "#B4B4BB"),
                                accent: Color(hex: "#0A84FF"),
                                hairline: Color(hex: "#E5E5EA"),
                                rowRadius: 8,
                                headerTimeSize: 40,
                                quoteIsSerif: true,
                                quoteHasMarks: false,
                                useCards: false,
                                useAccentBars: true,
                                detectIsSolid: false,
                                panelRadius: 16,
                                rowHeight: 52)
        case .glass:
            return ThemePalette(window: Color(hex: "#F5F7FA"),
                                surface: Color(hex: "#FFFFFF"),
                                surfaceAlt: Color(hex: "#FFFFFF"),
                                textPrimary: Color(hex: "#1D1D1F"),
                                textSecondary: Color(hex: "#5F6B76"),
                                textTertiary: Color(hex: "#8A94A0"),
                                accent: Color(hex: "#0A84FF"),
                                hairline: Color(hex: "#E0E6ED"),
                                rowRadius: 14,
                                headerTimeSize: 44,
                                quoteIsSerif: true,
                                quoteHasMarks: false,
                                useCards: true,
                                useAccentBars: false,
                                detectIsSolid: true,
                                panelRadius: 24,
                                rowHeight: 82)
        case .midnight:
            return ThemePalette(window: Color(hex: "#1C1C1E"),
                                surface: Color(hex: "#2C2C2E"),
                                surfaceAlt: Color(hex: "#242426"),
                                textPrimary: Color(hex: "#F5F5F7"),
                                textSecondary: Color(hex: "#98989D"),
                                textTertiary: Color(hex: "#7C7C80"),
                                accent: Color(hex: "#64D2FF"),
                                hairline: Color(hex: "#3A3A3C"),
                                rowRadius: 10,
                                headerTimeSize: 42,
                                quoteIsSerif: true,
                                quoteHasMarks: false,
                                useCards: false,
                                useAccentBars: true,
                                detectIsSolid: false,
                                panelRadius: 20,
                                rowHeight: 52)
        case .editorial:
            return ThemePalette(window: Color(hex: "#FAFAF8"),
                                surface: Color(hex: "#FAFAF8"),
                                surfaceAlt: Color(hex: "#F2F2ED"),
                                textPrimary: Color(hex: "#2E2A24"),
                                textSecondary: Color(hex: "#8B867A"),
                                textTertiary: Color(hex: "#B9B9B0"),
                                accent: Color(hex: "#C41E3A"),
                                hairline: Color(hex: "#E2E2DC"),
                                rowRadius: 4,
                                headerTimeSize: 52,
                                quoteIsSerif: true,
                                quoteHasMarks: true,
                                useCards: false,
                                useAccentBars: false,
                                detectIsSolid: false,
                                panelRadius: 4,
                                rowHeight: 66)
        }
    }
}

// MARK: - Main panel

struct MenuPanelView: View {
    @EnvironmentObject var store: TimeZoneStore

    private var palette: ThemePalette { ThemePalette.palette(for: store.theme) }

    var body: some View {
        VStack(spacing: 0) {
            HeaderView(palette: palette)
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .padding(.bottom, 14)

            DividerView(palette: palette)
                .padding(.horizontal, 12)

            ZoneListView(palette: palette)
                .frame(maxHeight: .infinity)

            DividerView(palette: palette)
                .padding(.horizontal, 12)

            FooterView(palette: palette)
                .padding(12)
        }
        .frame(minWidth: 320, minHeight: 420, maxHeight: .infinity)
        .background(palette.window)
        .onAppear {
            store.refreshAutoTimezoneFlag()
        }
    }
}

// MARK: - Header: avatar · quote · time

struct HeaderView: View {
    @EnvironmentObject var store: TimeZoneStore
    let palette: ThemePalette

    /// The highlighted zone: prefer the uuid-tracked current row, fall back to
    /// a lookup by IANA id (covers the case where the current row was deleted
    /// and the pointer was sanitized to nil).
    private var current: ZoneEntry? {
        if let u = store.currentZoneUUID,
           let z = store.zones.first(where: { $0.uuid == u }) { return z }
        return store.zones.first { $0.id == store.currentZoneIdentifier }
    }

    private var accent: Color { palette.accent }

    private var dateText: String {
        // The date must be formatted in the DISPLAYED zone, not the host one —
        // otherwise the header can show 01:30 on a Monday with "Sunday"
        // beneath it for an hour either side of midnight.
        TimeZoneStore.cachedFormatter(
            format: "EEEE, MMM d",
            timeZone: TimeZone(identifier: store.currentZoneIdentifier)
        ).string(from: store.now)
    }

    var body: some View {
        if store.theme == .editorial {
            editorialBody
        } else {
            HStack(alignment: .center, spacing: 14) {
                AvatarView(palette: palette)
                QuoteView(palette: palette)
                    .frame(maxWidth: .infinity, alignment: .leading)
                timeStack
            }
        }
    }

    // Editorial: avatar + label on top, big serif time, quote below
    private var editorialBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                AvatarView(palette: palette)
                VStack(alignment: .leading, spacing: 2) {
                    Text(current?.label ?? "Current")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(palette.textPrimary)
                    Text(dateText)
                        .font(.system(size: 12))
                        .foregroundColor(palette.textSecondary)
                }
            }
            .padding(.bottom, 6)

            Text(store.timeString(for: store.currentZoneIdentifier))
                .font(.system(size: palette.headerTimeSize, weight: .medium, design: .serif))
                .monospacedDigit()
                .foregroundColor(palette.textPrimary)
            Text("UTC\(TimeZoneStore.offsetString(for: store.currentZoneIdentifier)) · \(current?.label ?? "Local")")
                .font(.system(size: 13))
                .foregroundColor(palette.textSecondary)
                .padding(.bottom, 6)

            QuoteView(palette: palette)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var timeStack: some View {
        VStack(alignment: .trailing, spacing: 5) {
            HStack(spacing: 6) {
                Image(systemName: "clock.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(accent)
                Text(current?.label ?? "Current")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(palette.textPrimary)
                if store.isDST(in: store.currentZoneIdentifier) {
                    Text("DST")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.orange)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.orange.opacity(0.15)))
                }
            }
            Text(store.timeString(for: store.currentZoneIdentifier))
                .font(.system(size: palette.headerTimeSize, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundColor(palette.textPrimary)
            Text("\(dateText)  ·  UTC\(TimeZoneStore.offsetString(for: store.currentZoneIdentifier))")
                .font(.system(size: 11))
                .foregroundColor(palette.textSecondary)
        }
    }
}

// MARK: - Quote of the hour

struct QuoteView: View {
    @EnvironmentObject var store: TimeZoneStore
    let palette: ThemePalette

    private static let quotes: [String] = [
        "Time is the most fair — everyone gets twenty-four hours a day.",
        "An inch of time is an inch of gold, but gold cannot buy time.",
        "Time flows like a river — it never stops, day or night.",
        "Life passes like a white colt glimpsed through a crack.",
        "Time is like water in a sponge — squeeze and there is always more.",
        "Live each day as if it were your last.",
        "No prime years come twice, no morning repeats itself.",
        "Don't wait idly, lamenting the grey in your youth.",
        "Nothing is as fast and as slow, as long and as short, as common and as precious as time.",
        "You never step into the same river twice — new water always flows past you.",
        "Time has no present, eternity has no future or past.",
        "Yesterday cannot be recalled; today holds its own worries."
    ]

    private var quote: String {
        // Rotate by the hour of the DISPLAYED zone, not the host system zone —
        // "morning" quotes should match what the panel is actually showing.
        var cal = Calendar.current
        cal.timeZone = TimeZone(identifier: store.currentZoneIdentifier) ?? .current
        let hour = cal.component(.hour, from: store.now)
        return Self.quotes[hour % Self.quotes.count]
    }

    var body: some View {
        let text = palette.quoteHasMarks ? "「\(quote)」" : quote
        Text(text)
            .font(.system(size: palette.quoteHasMarks ? 14 : 12,
                          weight: .medium,
                          design: palette.quoteIsSerif ? .serif : .default))
            .italic()
            .foregroundColor(palette.textSecondary)
            .multilineTextAlignment(palette.quoteHasMarks ? .center : .leading)
            .lineLimit(4)
            .fixedSize(horizontal: false, vertical: true)
            .transition(.opacity)
            .id(quote)
    }
}

// MARK: - Divider

struct DividerView: View {
    let palette: ThemePalette
    var body: some View {
        Rectangle()
            .fill(palette.hairline)
            .frame(height: 1)
    }
}

// MARK: - Zone list

struct ZoneListView: View {
    @EnvironmentObject var store: TimeZoneStore
    let palette: ThemePalette

    var body: some View {
        ScrollView {
            LazyVStack(spacing: palette.useCards ? 10 : 2) {
                // Keyed by the entry's unique uuid, so Berlin + Frankfurt
                // (same IANA id) render as two distinct stable rows and hover
                // state never migrates to a neighbour after a middle delete.
                ForEach(store.zones, id: \.uuid) { zone in
                    ZoneRowView(palette: palette, zone: zone)
                }
                AddZoneRow(palette: palette)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
        }
    }
}

// MARK: - Add zone row (bottom of list)

struct AddZoneRow: View {
    @EnvironmentObject var store: TimeZoneStore
    let palette: ThemePalette

    var body: some View {
        Menu {
            // enumerated() so duplicate tz ids (Berlin & Frankfurt both
            // Europe/Berlin) render as separate menu rows without SwiftUI
            // complaining about duplicate ForEach ids.
            ForEach(Array(SettingsView.commonZones.enumerated()), id: \.offset) { _, item in
                Button("\(item.label)\(item.region.isEmpty ? "" : " · \(item.region)")") {
                    // Dedupe by (id, label) so Berlin and Frankfurt (same tz id,
                    // different names) can both be added.
                    guard !store.zones.contains(where: { $0.id == item.id && $0.label == item.label }) else { return }
                    store.zones.append(ZoneEntry(id: item.id,
                                                 label: item.label,
                                                 region: item.region,
                                                 color: store.nextZoneColor()))
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 12, weight: .medium))
                Text("Add time zone")
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundColor(palette.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
    }
}

struct ZoneRowView: View {
    @EnvironmentObject var store: TimeZoneStore
    let palette: ThemePalette
    let zone: ZoneEntry

    private var isCurrent: Bool { zone.uuid == store.currentZoneUUID }
    private var dayDiff: Int { store.dayDifference(for: zone) }
    private var offset: String { TimeZoneStore.offsetString(for: zone.id) }

    private var dayLabel: String {
        TimeZoneStore.dayLabel(for: dayDiff)
    }

    private var accent: Color { Color(hex: zone.color) }

    @State private var hovered = false

    var body: some View {
        Button {
            store.switchTo(zone)
        } label: {
            content
        }
        .buttonStyle(.plain)
        .disabled(store.isSwitching)
        .onHover { hovered = $0 }
    }

    private var hoverActions: some View {
        HStack(spacing: 2) {
            Menu {
                ForEach(Array(SettingsView.commonZones.enumerated()), id: \.offset) { _, item in
                    Button("\(item.label)\(item.region.isEmpty ? "" : " · \(item.region)")") {
                        replace(with: item)
                    }
                }
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(palette.textSecondary)
                    .frame(width: 22, height: 22)
            }
            .menuStyle(.borderlessButton)
            .accessibilityLabel("Replace \(zone.label)")

            Button {
                // Delete by unique uuid — deleting Frankfurt must not take
                // Berlin (same IANA id) with it.
                store.zones.removeAll { $0.uuid == zone.uuid }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundColor(isCurrent ? Color.gray.opacity(0.35) : Color.red.opacity(0.7))
            }
            .buttonStyle(.plain)
            .disabled(isCurrent)
            .accessibilityLabel("Remove \(zone.label)")
        }
        .frame(width: 46)
        .opacity(hovered ? 1 : 0)
        // Invisible buttons must not be clickable — without this, the 46pt
        // strip is a silent delete/replace trigger even before the row is
        // hovered.
        .allowsHitTesting(hovered)
    }

    private func replace(with item: (id: String, label: String, region: String)) {
        guard let idx = store.zones.firstIndex(where: { $0.uuid == zone.uuid }) else { return }
        let wasCurrent = zone.uuid == store.currentZoneUUID
        // Keep the same uuid across the replacement so SwiftUI ForEach identity,
        // hover state and the current-zone pointer all stay valid.
        store.zones[idx] = ZoneEntry(id: item.id,
                                     label: item.label,
                                     region: item.region,
                                     color: zone.color,
                                     uuid: zone.uuid)
        if wasCurrent {
            store.currentZoneUUID = store.zones[idx].uuid
            store.setCurrentZone(item.id, uuid: store.zones[idx].uuid)
        }
    }

    @ViewBuilder
    private var content: some View {
        if palette.useCards {
            // Glass: card with accent dot
            HStack(spacing: 10) {
                Circle()
                    .fill(accent)
                    .frame(width: 9, height: 9)
                VStack(alignment: .leading, spacing: 2) {
                    Text(zone.region.isEmpty ? zone.label : "\(zone.label) · \(zone.region)")
                        .font(.system(size: 14, weight: isCurrent ? .semibold : .regular))
                        .foregroundColor(palette.textPrimary)
                        .lineLimit(1)
                    Text(zone.id)
                        .font(.system(size: 11))
                        .foregroundColor(palette.textSecondary)
                        .lineLimit(1)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    HStack(spacing: 4) {
                        if isCurrent {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 10))
                                .foregroundColor(accent)
                        }
                        Text(store.timeString(for: zone))
                            .font(.system(size: 20, weight: .medium))
                            .monospacedDigit()
                            .foregroundColor(palette.textPrimary)
                    }
                    Text("\(dayLabel)  ·  UTC\(offset)")
                        .font(.system(size: 10))
                        .foregroundColor(palette.textSecondary)
                }
                hoverActions
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: palette.rowRadius)
                    .fill(palette.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: palette.rowRadius)
                    .stroke(palette.hairline, lineWidth: 1)
            )
        } else if palette.useAccentBars {
            // Minimal / Midnight: 4px accent bar
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(accent)
                    .frame(width: 4, height: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(zone.region.isEmpty ? zone.label : "\(zone.label) · \(zone.region)")
                        .font(.system(size: 13, weight: isCurrent ? .semibold : .regular))
                        .foregroundColor(palette.textPrimary)
                        .lineLimit(1)
                    Text(zone.id)
                        .font(.system(size: 10))
                        .foregroundColor(palette.textSecondary)
                        .lineLimit(1)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    HStack(spacing: 4) {
                        if isCurrent {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 10))
                                .foregroundColor(accent)
                        }
                        Text(store.timeString(for: zone))
                            .font(.system(size: 15, weight: .medium))
                            .monospacedDigit()
                            .foregroundColor(palette.textPrimary)
                    }
                    Text("\(dayLabel)  ·  UTC\(offset)")
                        .font(.system(size: 10))
                        .foregroundColor(palette.textSecondary)
                }
                hoverActions
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: palette.rowRadius)
                    .fill(isCurrent ? accent.opacity(store.theme == .midnight ? 0.18 : 0.09) : Color.clear)
            )
            .contentShape(Rectangle())
        } else {
            // Editorial: hairline rows, no bars
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(zone.region.isEmpty ? zone.label : "\(zone.label) · \(zone.region)")
                        .font(.system(size: 14, weight: isCurrent ? .semibold : .regular))
                        .foregroundColor(palette.textPrimary)
                        .lineLimit(1)
                    Text(zone.id)
                        .font(.system(size: 11))
                        .foregroundColor(palette.textSecondary)
                        .lineLimit(1)
                }
                Spacer()
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if isCurrent {
                        Text("\(dayLabel) · UTC\(offset)")
                            .font(.system(size: 11))
                            .foregroundColor(palette.accent)
                    } else {
                        Text("\(dayLabel) · UTC\(offset)")
                            .font(.system(size: 11))
                            .foregroundColor(palette.textTertiary)
                    }
                    Text(store.timeString(for: zone))
                        .font(.system(size: 17, weight: .medium))
                        .monospacedDigit()
                        .foregroundColor(palette.textPrimary)
                }
                hoverActions
            }
            .padding(.vertical, 8)
            .overlay(alignment: .bottom) {
                DividerView(palette: palette)
                    .opacity(0.5)
            }
            .contentShape(Rectangle())
        }
    }
}

// MARK: - Footer

struct FooterView: View {
    @EnvironmentObject var store: TimeZoneStore
    let palette: ThemePalette

    var body: some View {
        VStack(spacing: 10) {
            detectButton

            if let d = store.detected {
                HStack(spacing: 8) {
                    Image(systemName: "mappin.and.ellipse")
                        .font(.system(size: 11))
                        .foregroundColor(palette.accent)
                    Text(d.city.isEmpty ? d.timezone : "\(d.city) · \(d.timezone)")
                        .font(.system(size: 12))
                        .foregroundColor(palette.textPrimary)
                        .lineLimit(1)
                    Spacer()
                    Button("Switch") {
                        store.confirmDetectedZone()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(store.isSwitching)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 8).fill(palette.accent.opacity(0.08)))
            }

            if store.autoTimezoneEnabled {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.orange)
                    Text("Auto timezone is on — switches may be reverted")
                        .font(.system(size: 11))
                        .foregroundColor(palette.textSecondary)
                    Spacer()
                    Button("Settings…") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.datetime") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.link)
                    .font(.system(size: 11))
                }
            }

            if let err = store.lastError {
                Text(err)
                    .font(.system(size: 10))
                    .foregroundColor(.red)
                    .lineLimit(3)
            }

            HStack {
                Button {
                    store.openSettings()
                } label: {
                    Label("Settings", systemImage: "gearshape")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundColor(palette.textSecondary)

                Spacer()

                Button("Quit TravelTime") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundColor(palette.textSecondary)
            }
            .padding(.top, 2)
        }
    }

    @ViewBuilder
    private var detectButton: some View {
        if palette.detectIsSolid {
            Button {
                store.detectLocation()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: store.isDetecting ? "arrow.triangle.2.circlepath" : "location.fill")
                        .font(.system(size: 12, weight: .medium))
                    Text(store.isDetecting ? "Detecting…" : "Detect current location")
                        .font(.system(size: 13, weight: .medium))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(Capsule().fill(palette.accent))
                .foregroundColor(.white)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(store.isDetecting)
        } else {
            Button {
                store.detectLocation()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: store.isDetecting ? "arrow.triangle.2.circlepath" : "location.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(palette.accent)
                    Text(store.isDetecting ? "Detecting…" : "Detect current location")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(palette.textPrimary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(
                    Capsule().fill(
                        store.theme == .editorial
                            ? Color.clear
                            : store.theme == .midnight ? palette.surface : Color.primary.opacity(0.05)
                    )
                )
                .overlay(
                    store.theme == .editorial
                        ? nil
                        : Capsule().stroke(palette.hairline, lineWidth: store.theme == .midnight ? 1 : 0)
                )
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(store.isDetecting)
        }
    }
}

// MARK: - Avatar

struct AvatarView: View {
    @EnvironmentObject var store: TimeZoneStore
    let palette: ThemePalette

    private var isDay: Bool { store.isDaytime(in: store.currentZoneIdentifier) }

    /// Cached in the store — never re-decoded from disk on every redraw.
    private var nsImage: NSImage? { store.avatarImage }

    var body: some View {
        Button {
            store.chooseAvatar()
        } label: {
            ZStack {
                Circle()
                    .fill(store.theme == .midnight ? palette.surface : Color.primary.opacity(0.06))
                    .frame(width: 64, height: 64)
                if let img = nsImage {
                    Image(nsImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 56, height: 56)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.white.opacity(0.6), lineWidth: 1.5))
                } else {
                    Image(systemName: isDay ? "sun.max.fill" : "moon.stars.fill")
                        .font(.system(size: 24))
                        .foregroundColor(isDay ? Color.orange : Color.indigo)
                }
                // Bottom corners: day/night indicator (left) + camera hint (right).
                VStack {
                    Spacer()
                    HStack {
                        Image(systemName: isDay ? "sun.max.fill" : "moon.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                            .padding(4)
                            .background(Circle().fill(isDay ? Color.orange : Color.indigo))
                        Spacer()
                        Image(systemName: "camera.fill")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.white)
                            .padding(3)
                            .background(Circle().fill(Color.black.opacity(0.55)))
                    }
                }
                .frame(width: 64, height: 64)
            }
        }
        .buttonStyle(.plain)
        .help("Click to choose a photo")
    }
}

// MARK: - Legacy menu bar label (kept for potential status item reuse)

struct MenuBarLabel: View {
    @EnvironmentObject var store: TimeZoneStore

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "clock")
                .font(.system(size: 12, weight: .medium))
            Text(store.menuBarText)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
        }
    }
}

// MARK: - Color helper

extension Color {
    /// Parses "#RRGGBB", "RRGGBB", 3-digit shorthand and 8-digit "#RRGGBBAA".
    /// Invalid input falls back to a neutral gray instead of silently black.
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        let expanded: String
        switch s.count {
        case 3: expanded = s.map { "\($0)\($0)" }.joined()
        case 6, 8: expanded = s
        default:
            self.init(.sRGB, red: 0.5, green: 0.5, blue: 0.5, opacity: 1)
            return
        }
        var value: UInt64 = 0
        guard Scanner(string: expanded).scanHexInt64(&value) else {
            self.init(.sRGB, red: 0.5, green: 0.5, blue: 0.5, opacity: 1)
            return
        }
        let r = Double((value >> 16) & 0xFF) / 255.0
        let g = Double((value >> 8) & 0xFF) / 255.0
        let b = Double(value & 0xFF) / 255.0
        let a = s.count == 8 ? Double(value & 0xFF) / 255.0 : 1
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}
