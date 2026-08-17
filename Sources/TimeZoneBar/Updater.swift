import Foundation
import AppKit
import CryptoKit

struct GitHubRelease: Decodable {
    struct Asset: Decodable {
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
            case .idle: return "检查更新"
            case .checking: return "检查中…"
            case .available: return "更新"
            case .downloading: return "下载中…"
            case .upToDate: return "已是最新"
            case .error: return "重试"
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

    /// 检查 GitHub 最新 Release
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
            state = .error("检查更新失败：\(error.localizedDescription)")
        }
    }

    /// 下载 → SHA256 校验 → 解压 → 管理员替换自身 → 重启
    func update(release: GitHubRelease) async {
        state = .downloading
        guard let asset = release.assets.first(where: { $0.name.hasSuffix(".zip") }),
              let url = URL(string: asset.browser_download_url) else {
            state = .error("未找到安装包资源")
            return
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            // SHA256 校验（发布时写在 Release 正文的 SHA256: 行）
            let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            if let expected = sha256FromBody(release.body), expected.lowercased() != digest {
                state = .error("安装包校验失败（SHA256 不匹配），已中止")
                return
            }
            // 解压到临时目录
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
                state = .error("安装包解压失败")
                return
            }
            // 管理员权限：删除旧 App → 拷贝新 App → 重新打开
            let script = """
            do shell script "rm -rf " & quoted form of "/Applications/TimeZoneBar.app" & " && cp -R " & quoted form of "\(newApp.path)" & " /Applications/TimeZoneBar.app && open " & quoted form of "/Applications/TimeZoneBar.app" with administrator privileges
            """
            try await PrivilegedRunner.run(script: script)
            state = .idle
            NSApp.terminate(nil)   // 替换成功，退出旧实例，让新实例接管
        } catch {
            state = .error("更新失败：\(error.localizedDescription)")
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
