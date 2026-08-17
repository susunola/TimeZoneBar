import SwiftUI
import AppKit

struct MenuPanelView: View {
    @EnvironmentObject var store: TimeZoneStore

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("World Clock")
                    .font(.headline)
                Spacer()
                if store.isSwitching {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding(.bottom, 4)

            ForEach(store.zones) { zone in
                ZoneRowView(zone: zone)
            }

            Divider()
                .padding(.vertical, 4)

            DetectSection()

            if store.autoTimezoneEnabled {
                Divider()
                    .padding(.vertical, 4)
                AutoTimezoneWarning()
            }

            if let err = store.lastError {
                Text(err)
                    .font(.caption)
                    .foregroundColor(.red)
                    .lineLimit(3)
                    .padding(.top, 2)
            }

            Divider()
                .padding(.vertical, 4)

            HStack(spacing: 16) {
                Button("Settings…") {
                    store.openSettings()
                }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundColor(.secondary)

                Spacer()

                Button("Quit TimeZoneBar") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            }
        }
        .padding(10)
        .frame(width: 330)
    }
}

struct ZoneRowView: View {
    @EnvironmentObject var store: TimeZoneStore
    let zone: ZoneEntry

    private var isCurrent: Bool { zone.id == store.currentZoneIdentifier }
    private var dayDiff: Int { store.dayDifference(for: zone) }
    private var offset: String { TimeZoneStore.offsetString(for: zone.id) }

    private var dayLabel: String {
        switch dayDiff {
        case -1: return "Yesterday · UTC\(offset)"
        case 1: return "Tomorrow · UTC\(offset)"
        default: return "Today · UTC\(offset)"
        }
    }

    var body: some View {
        Button {
            store.switchTo(zone)
        } label: {
            HStack(spacing: 10) {
                Circle()
                    .fill(Color(hex: zone.color))
                    .frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(zone.region.isEmpty ? zone.label : "\(zone.label) · \(zone.region)")
                            .font(.system(size: 13, weight: isCurrent ? .semibold : .regular))
                        if store.isDST(in: zone.id) {
                            Text("DST")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(.orange)
                                .padding(.horizontal, 3)
                                .padding(.vertical, 1)
                                .background(
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(Color.orange.opacity(0.15))
                                )
                        }
                        if isCurrent {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.blue)
                        }
                    }
                    Text(zone.id)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    HStack(spacing: 4) {
                        // Day/night indicator
                        Image(systemName: store.isDaytime(in: zone.id) ? "sun.max.fill" : "moon.fill")
                            .font(.system(size: 10))
                            .foregroundColor(store.isDaytime(in: zone.id) ? .orange : .indigo)
                        Text(store.timeString(for: zone))
                            .font(.system(size: 15, weight: .medium, design: .monospaced))
                    }
                    Text(dayLabel)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isCurrent ? Color.blue.opacity(0.08) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(store.isSwitching)
    }
}

struct DetectSection: View {
    @EnvironmentObject var store: TimeZoneStore

    var body: some View {
        VStack(spacing: 6) {
            Button {
                store.detectLocation()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: store.isDetecting ? "arrow.triangle.2.circlepath" : "location")
                        .font(.system(size: 12))
                        .foregroundColor(.blue)
                    Text(store.isDetecting ? "Detecting location…" : "Detect current location")
                        .font(.system(size: 13, weight: .medium))
                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.primary.opacity(0.05))
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(store.isDetecting)

            if let d = store.detected {
                HStack(spacing: 8) {
                    Image(systemName: "mappin.and.ellipse")
                        .font(.system(size: 11))
                        .foregroundColor(.blue)
                    Text(d.city.isEmpty ? d.timezone : "\(d.city) · \(d.timezone)")
                        .font(.system(size: 12))
                    Spacer()
                    Button("Switch") {
                        store.confirmDetectedZone()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(store.isSwitching)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
        }
    }
}

struct AutoTimezoneWarning: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundColor(.orange)
            VStack(alignment: .leading, spacing: 1) {
                Text("\"Set time zone automatically\" is on")
                    .font(.system(size: 12, weight: .medium))
                Text("Manual switches may be reverted by macOS")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button("Open Settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.datetime") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.orange.opacity(0.1))
        )
    }
}

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

extension Color {
    init(hex: String) {
        var value: UInt64 = 0
        var s = hex
        if s.hasPrefix("#") { s.removeFirst() }
        Scanner(string: s).scanHexInt64(&value)
        let r = Double((value >> 16) & 0xFF) / 255.0
        let g = Double((value >> 8) & 0xFF) / 255.0
        let b = Double(value & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }
}
