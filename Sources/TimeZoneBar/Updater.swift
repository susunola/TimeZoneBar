import Foundation
import AppKit
import CryptoKit

struct GitHubRelease: Decodable {
    struct Asset: Decodable {
        let id: Int
        let name: String
        let browser_download_url: String
    }
    let tag_name: String
    let body: String?
    let assets: [Asset]
}

@MainActor
final class Updater: ObservableObject {
    static let repoOwner = "susunola"
    static let repoName = "TimeZoneBar"

    enum State {
        case idle
        case checking
        case available(version: String, release: GitHubRelease)
        case downloading
        case upToDate
        case error(String)

        var buttonTitle: String {
            switch self {
            case .idle: return "Check for Updates"
            case .checking: return "Checking…"
            case .available: return "Update"
            case .downloading: return "Downloading…"
            case .upToDate: return "Up to Date"
            case .error: return "Retry"
            }
        }

        var isBusy: Bool {
            switch self {
            case .checking, .downloading: return true
            default: return false
            }
        }
    }

    @Published var state: State = .idle

    var isBusy: Bool { state.isBusy }

    private static var latestAPI: URL {
        URL(string: "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest")!
    }

    /// Checks the latest GitHub release
    func check() async {
        state = .checking
        var req = URLRequest(url: Self.latestAPI)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 10
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            let latest = release.tag_name.replacingOccurrences(of: "v", with: "")
            let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
            if latest.compare(current, options: .numeric) == .orderedDescending {
                state = .available(version: latest, release: release)
            } else {
                state = .upToDate
            }
        } catch {
            state = .error("Update check failed: \(error.localizedDescription)")
        }
    }

    /// Download -> verify SHA256 -> unzip -> replace itself with admin rights -> relaunch
    func update(release: GitHubRelease) async {
        state = .downloading
        guard let asset = release.assets.first(where: { $0.name.hasSuffix(".zip") }) else {
            state = .error("No installer asset found in the release")
            return
        }
        // Download via the API asset endpoint (browser_download_url can 404; this endpoint is reliable)
        guard let url = URL(string: "https://api.github.com/repos/\(Self.repoOwner)/\(Self.repoName)/releases/assets/\(asset.id)") else {
            state = .error("Invalid installer URL")
            return
        }
        do {
            var req = URLRequest(url: url)
            req.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
            req.timeoutInterval = 60
            let (data, _) = try await URLSession.shared.data(for: req)
            // Verify SHA256 (published on the "SHA256:" line of the release notes)
            let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            if let expected = sha256FromBody(release.body), expected.lowercased() != digest {
                state = .error("Checksum mismatch (SHA256), installation aborted")
                return
            }
            // Unzip into a temporary directory
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent("tzbar-update-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
            let zipPath = tmp.appendingPathComponent("TimeZoneBar.app.zip")
            try data.write(to: zipPath)

            let unzip = Process()
            unzip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            unzip.arguments = ["-xk", zipPath.path, tmp.path]
            try unzip.run()
            unzip.waitUntilExit()

            let newApp = tmp.appendingPathComponent("TimeZoneBar.app")
            guard FileManager.default.fileExists(atPath: newApp.path) else {
                state = .error("Could not unzip the installer")
                return
            }
            // With admin rights: remove the old app, copy the new one, relaunch
            let script = """
            do shell script "rm -rf " & quoted form of "/Applications/TimeZoneBar.app" & " && cp -R " & quoted form of "\(newApp.path)" & " /Applications/TimeZoneBar.app && open " & quoted form of "/Applications/TimeZoneBar.app" with administrator privileges
            """
            try await PrivilegedRunner.run(script: script)
            state = .idle
            NSApp.terminate(nil)   // Replaced successfully; quit so the new instance takes over
        } catch {
            state = .error("Update failed: \(error.localizedDescription)")
        }
    }

    private func sha256FromBody(_ body: String?) -> String? {
        guard let body else { return nil }
        return body.split(separator: "\n").compactMap { line -> String? in
            let l = line.trimmingCharacters(in: .whitespaces)
            guard l.uppercased().hasPrefix("SHA256:") else { return nil }
            return l.replacingOccurrences(of: "SHA256:", with: "")
                .trimmingCharacters(in: .whitespaces)
                .lowercased()
        }.first
    }
}
