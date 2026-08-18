import Foundation

enum ZoneSwitchError: LocalizedError {
    case scriptUnavailable
    case userCanceled
    case adminRejected(String)

    var errorDescription: String? {
        switch self {
        case .scriptUnavailable:
            return "Could not launch the osascript process"
        case .userCanceled:
            // Should never be shown — callers check for this case and stay silent.
            return nil
        case .adminRejected(let msg):
            let trimmed = msg.trimmingCharacters(in: .whitespacesAndNewlines)
            return "Authorization failed: \(trimmed.isEmpty ? "unknown error" : trimmed)"
        }
    }
}

/// Runs a privileged command through the macOS authorization dialog (osascript subprocess).
/// Never blocks the main thread and never stores the password.
///
/// Execution happens on a background queue; the method returns after the child
/// finishes or after `timeout` seconds (whichever comes first). On timeout the
/// child process is terminated so a dismissed/ignored authorization dialog can
/// never leave a dangling osascript around.
enum PrivilegedRunner {
    static func run(script: String, timeout: TimeInterval = 15) async throws {
        let (status, output) = await Task.detached(priority: .userInitiated) { () -> (Int32, String) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", script]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            do {
                try process.run()
            } catch {
                return (-1, "launch failed: \(error.localizedDescription)")
            }

            // Blocking read runs on this background thread — the main thread
            // stays responsive while the admin dialog is up.
            let queue = DispatchQueue(label: "tzbar.osascript", qos: .userInitiated)
            var output = ""
            var status: Int32 = -1
            let sema = DispatchSemaphore(value: 0)
            queue.async {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                output = String(data: data, encoding: .utf8) ?? ""
                process.waitUntilExit()
                status = process.terminationStatus
                sema.signal()
            }
            // Wait with a hard cap; terminate the child if the user never
            // answers the authorization dialog.
            if sema.wait(timeout: .now() + timeout) == .timedOut {
                process.terminate()
                _ = sema.wait(timeout: .now() + 2)   // give it a moment to clean up
                return (-2, "Timed out waiting for authorization")
            }
            return (status, output)
        }.value

        if status == -1 {
            throw ZoneSwitchError.scriptUnavailable
        }
        if status == -2 {
            throw ZoneSwitchError.adminRejected("Timed out waiting for authorization")
        }
        if status != 0 {
            // osascript returns 128 when the user dismisses the authorization
            // dialog. That is the user explicitly saying "no thanks" — not an
            // error worth surfacing in the UI.
            if status == 128 || output.contains("User canceled") {
                throw ZoneSwitchError.userCanceled
            }
            throw ZoneSwitchError.adminRejected(output)
        }
    }
}

enum SystemZoneSwitcher {
    /// Switches the system time zone.
    ///
    /// The identifier is validated against the system's known IANA list before
    /// it ever reaches a shell string — this is the primary defense against
    /// command injection via untrusted input (e.g. a spoofed geo-location
    /// response). After validation the value can only contain letters, digits,
    /// `_`, `/` and `-`, which are inert inside the quoted AppleScript string.
    static func switchTimeZone(to identifier: String) async throws {
        guard TimeZone.knownTimeZoneIdentifiers.contains(identifier) else {
            throw ZoneSwitchError.adminRejected("Invalid time zone: \(identifier)")
        }
        let script = "do shell script \"/usr/sbin/systemsetup -settimezone '\(identifier)'\" with administrator privileges"
        try await PrivilegedRunner.run(script: script)
    }
}
