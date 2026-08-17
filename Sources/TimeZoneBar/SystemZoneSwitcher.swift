import Foundation

enum ZoneSwitchError: LocalizedError {
    case scriptUnavailable
    case adminRejected(String)

    var errorDescription: String? {
        switch self {
        case .scriptUnavailable:
            return "Could not launch the osascript process"
        case .adminRejected(let msg):
            let trimmed = msg.trimmingCharacters(in: .whitespacesAndNewlines)
            return "Authorization failed: \(trimmed.isEmpty ? "unknown error" : trimmed)"
        }
    }
}

/// Runs a privileged command through the macOS authorization dialog (osascript subprocess).
/// Never blocks the main thread and never stores the password.
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
            let msg = String(data: data, encoding: .utf8) ?? "unknown error"
            throw ZoneSwitchError.adminRejected(msg)
        }
    }
}

enum SystemZoneSwitcher {
    /// Switches the system time zone
    static func switchTimeZone(to identifier: String) async throws {
        let escaped = identifier.replacingOccurrences(of: "'", with: "\\'")
        let script = "do shell script \"/usr/sbin/systemsetup -settimezone '\(escaped)'\" with administrator privileges"
        try await PrivilegedRunner.run(script: script)
    }
}
