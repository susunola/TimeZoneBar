import Foundation

enum ZoneSwitchError: LocalizedError {
    case scriptUnavailable
    case adminRejected(String)

    var errorDescription: String? {
        switch self {
        case .scriptUnavailable:
            return "无法启动 osascript 进程"
        case .adminRejected(let msg):
            let trimmed = msg.trimmingCharacters(in: .whitespacesAndNewlines)
            return "管理员授权失败：\(trimmed.isEmpty ? "未知错误" : trimmed)"
        }
    }
}

/// 通过 macOS 系统授权框（osascript 子进程）执行需要管理员权限的命令。
/// 授权期间不阻塞主线程，不保存任何密码。
enum PrivilegedRunner {
    static func run(script: String) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            throw ZoneSwitchError.scriptUnavailable
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            let msg = String(data: data, encoding: .utf8) ?? "未知错误"
            throw ZoneSwitchError.adminRejected(msg)
        }
    }
}

enum SystemZoneSwitcher {
    /// 切换系统时区
    static func switchTimeZone(to identifier: String) async throws {
        let escaped = identifier.replacingOccurrences(of: "'", with: "\\'")
        let script = "do shell script \"/usr/sbin/systemsetup -settimezone '\(escaped)'\" with administrator privileges"
        try await PrivilegedRunner.run(script: script)
    }
}
