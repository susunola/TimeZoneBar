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
    static let repoName = "TravelTime"

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
            let (data, response) = try await URLSession.shared.data(for: req)
            
            // #3: Check HTTP status code
            if let httpResponse = response as? HTTPURLResponse,
               httpResponse.statusCode != 200 {
                if httpResponse.statusCode == 403 {
                    // Unauthenticated GitHub API is rate-limited to 60 req/h.
                    state = .error("GitHub API rate limit reached — try again in about an hour")
                } else {
                    state = .error("GitHub API error: HTTP \(httpResponse.statusCode)")
                }
                return
            }
            
            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            
            // #2: More robust version parsing
            let latest = parseVersion(release.tag_name)
            let current = parseVersion(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0")
            
            if isVersionGreater(latest, than: current) {
                state = .available(version: release.tag_name, release: release)
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
            
            let (data, response) = try await URLSession.shared.data(for: req)
            
            // #3: Check HTTP status code for download
            if let httpResponse = response as? HTTPURLResponse,
               httpResponse.statusCode != 200 {
                state = .error("Download failed: HTTP \(httpResponse.statusCode)")
                return
            }
            
            // #4: Fail-closed SHA256 verification
            let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            if let expected = sha256FromBody(release.body) {
                if expected.lowercased() != digest {
                    state = .error("Checksum mismatch (SHA256), installation aborted")
                    return
                }
            } else {
                // No checksum found in release notes - fail closed
                state = .error("No SHA256 checksum found in release notes, installation aborted for security")
                return
            }
            
            // Unzip into a temporary directory
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent("tzbar-update-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
            let zipPath = tmp.appendingPathComponent("TravelTime.app.zip")
            try data.write(to: zipPath)

            let unzip = Process()
            unzip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            unzip.arguments = ["-xk", zipPath.path, tmp.path]
            try unzip.run()
            unzip.waitUntilExit()
            
            // #5: Check ditto exit code
            if unzip.terminationStatus != 0 {
                state = .error("Failed to unzip the installer (exit code: \(unzip.terminationStatus))")
                return
            }

            let newApp = tmp.appendingPathComponent("TravelTime.app")
            guard FileManager.default.fileExists(atPath: newApp.path) else {
                state = .error("Could not unzip the installer")
                return
            }
            // With admin rights: remove the old app, copy the new one, relaunch
            let script = """
            do shell script "rm -rf " & quoted form of "/Applications/TravelTime.app" & " && cp -R " & quoted form of "\(newApp.path)" & " /Applications/TravelTime.app && open " & quoted form of "/Applications/TravelTime.app" with administrator privileges
            """
            try await PrivilegedRunner.run(script: script)
            // Clean up the download/unzip scratch dir before relaunching.
            try? FileManager.default.removeItem(at: tmp)
            state = .idle
            NSApp.terminate(nil)   // Replaced successfully; quit so the new instance takes over
        } catch {
            state = .error("Update failed: \(error.localizedDescription)")
        }
    }

    /// Parse version string to comparable array of integers.
    /// Handles "v1.2.3", "1.2.3", "1.2". Only the leading digits of the first
    /// three dot-separated segments are kept, so prerelease suffixes like
    /// "2.0.0-beta.1" never inflate the version (internal for tests).
    func parseVersion(_ versionString: String) -> [Int] {
        let cleaned = versionString.replacingOccurrences(of: "v", with: "").trimmingCharacters(in: .whitespaces)
        return cleaned.split(separator: ".")
            .prefix(3)
            .compactMap { segment -> Int? in
                let digits = segment.prefix(while: { $0.isNumber })
                return digits.isEmpty ? nil : Int(digits)
            }
    }

    /// Compare two version arrays: returns true if v1 > v2 (internal for tests)
    func isVersionGreater(_ v1: [Int], than v2: [Int]) -> Bool {
        let maxLength = max(v1.count, v2.count)
        for i in 0..<maxLength {
            let num1 = i < v1.count ? v1[i] : 0
            let num2 = i < v2.count ? v2[i] : 0
            if num1 > num2 { return true }
            if num1 < num2 { return false }
        }
        return false
    }

    func sha256FromBody(_ body: String?) -> String? {
        guard let body else { return nil }
        // Support multiple formats: "SHA256: abc123", "sha256: abc123", "SHA256 abc123", "Checksum: abc123"
        let patterns = ["SHA256:", "sha256:", "SHA 256:", "Checksum:"]
        for line in body.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            for pattern in patterns {
                if trimmed.uppercased().contains(pattern.uppercased()) {
                    let afterPattern = trimmed.split(separator: ":", maxSplits: 1).last ?? ""
                    let hash = afterPattern.trimmingCharacters(in: .whitespaces)
                    if hash.count == 64 {  // SHA256 is 64 hex chars
                        return hash.lowercased()
                    }
                }
            }
        }
        return nil
    }
}
