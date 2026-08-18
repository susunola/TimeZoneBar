import SwiftUI

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

/// A single selectable time zone in the add picker.
struct ZoneCandidate: Identifiable {
    let id: String          // IANA identifier
    let label: String       // display name
    let region: String      // continent / sub-region
}

struct AddZoneRow: View {
    @EnvironmentObject var store: TimeZoneStore
    let palette: ThemePalette

    @State private var showPicker = false
    @State private var query = ""

    /// Full IANA list (common zones first), built once. `filtered` then drops
    /// anything already in the panel and applies the search query.
    private static let allCandidates: [ZoneCandidate] = {
        var seen = Set(SettingsView.commonZones.map { $0.id })
        var result = SettingsView.commonZones.map {
            ZoneCandidate(id: $0.id, label: $0.label, region: $0.region)
        }
        for id in TimeZone.knownTimeZoneIdentifiers {
            guard !seen.contains(id) else { continue }
            let parts = id.split(separator: "/")
            let label = (parts.last.map(String.init) ?? id).replacingOccurrences(of: "_", with: " ")
            let region = parts.dropLast().last.map(String.init) ?? ""
            result.append(ZoneCandidate(id: id, label: label, region: region))
            seen.insert(id)
        }
        return result
    }()

    private var filtered: [ZoneCandidate] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let existing = Set(store.zones.map { $0.id })
        return Self.allCandidates.filter { candidate in
            guard !existing.contains(candidate.id) else { return false }
            if q.isEmpty { return true }
            return candidate.id.lowercased().contains(q)
                || candidate.label.lowercased().contains(q)
                || candidate.region.lowercased().contains(q)
        }
    }

    var body: some View {
        Button {
            showPicker.toggle()
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
        .buttonStyle(.plain)
        .popover(isPresented: $showPicker, arrowEdge: .top) {
            ZonePickerPopover(candidates: Self.allCandidates,
                              existingIDs: Set(store.zones.map { $0.id }),
                              query: $query,
                              onAdd: { item in
                                  store.zones.append(ZoneEntry(id: item.id,
                                                               label: item.label,
                                                               region: item.region,
                                                               color: store.nextZoneColor()))
                                  showPicker = false
                              })
        }
    }
}

/// Searchable, scrollable picker for adding any IANA time zone.
struct ZonePickerPopover: View {
    let candidates: [ZoneCandidate]
    let existingIDs: Set<String>
    @Binding var query: String
    let onAdd: (ZoneCandidate) -> Void

    private var filtered: [ZoneCandidate] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return candidates.filter { candidate in
            guard !existingIDs.contains(candidate.id) else { return false }
            if q.isEmpty { return true }
            return candidate.id.lowercased().contains(q)
                || candidate.label.lowercased().contains(q)
                || candidate.region.lowercased().contains(q)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField("Search time zones", text: $query)
                .textFieldStyle(.roundedBorder)
                .padding(10)
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(filtered) { item in
                        Button {
                            onAdd(item)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.label)
                                    .font(.system(size: 13, weight: .medium))
                                Text(item.id)
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Divider()
                    }
                }
            }
            .frame(width: 300, height: 320)
        }
        .frame(width: 300)
    }
}

// MARK: - Zone row

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
        // Keyboard / VoiceOver users have no pointer, so the hover-only
        // replace/remove controls are unreachable. A context menu exposes
        // Switch / Replace / Remove through the standard accessibility path
        // (Control-Option-Shift-M / right-click), keeping every row action
        // operable without a mouse.
        .contextMenu {
            if !isCurrent {
                Button("Switch to \(zone.label)") { store.switchTo(zone) }
            }
            Menu("Replace with…") {
                ForEach(Array(SettingsView.commonZones.enumerated()), id: \.offset) { _, item in
                    Button("\(item.label)\(item.region.isEmpty ? "" : " · \(item.region)")") {
                        replace(with: item)
                    }
                }
            }
            Divider()
            Button("Remove \(zone.label)", role: .destructive) {
                store.zones.removeAll { $0.uuid == zone.uuid }
            }
            .disabled(isCurrent)
        }
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
