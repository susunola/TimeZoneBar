import SwiftUI
import AppKit

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
