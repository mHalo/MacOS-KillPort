import Foundation

// MARK: - Process Killer

/// Handles termination of processes by PID.
///
/// The kill strategy follows a graceful-to-forceful escalation:
/// 1. Send `SIGTERM` (allows the process to clean up gracefully).
/// 2. Wait ~1 second; if the process still exists, send `SIGKILL` (immediate termination).
/// 3. If both fail (typically due to insufficient privileges), escalate to
///    `osascript` with administrator privileges, which prompts the user for their password.
final class ProcessKiller: Sendable {

    /// The path to the kill binary.
    private let killPath = "/bin/kill"

    /// The path to the osascript binary (for privilege escalation).
    private let osascriptPath = "/usr/bin/osascript"

    /// Attempts to terminate a process by PID using escalating signals.
    ///
    /// - Parameter pid: The process ID to terminate.
    /// - Returns: The result of the kill operation.
    func kill(pid: Int) async -> KillResult {
        // Step 1: Try SIGTERM (graceful termination).
        let termSucceeded = runKillCommand(pid: pid, signal: "TERM")

        if termSucceeded {
            // Give the process time to shut down gracefully.
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second

            if !processExists(pid: pid) {
                return .success
            }
        }

        // Step 2: Try SIGKILL (forceful termination).
        let killSucceeded = runKillCommand(pid: pid, signal: "KILL")

        if killSucceeded {
            // SIGKILL is immediate, but give the kernel a moment to reap the process.
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds

            if !processExists(pid: pid) {
                return .success
            }
        }

        // Step 3: If the process still exists, escalate to administrator privileges.
        // This handles the case where the user doesn't own the process.
        if processExists(pid: pid) {
            return await killWithAdminPrivileges(pid: pid)
        }

        // If the process doesn't exist at this point, it was likely already gone.
        return .success
    }

    // MARK: - Private Helpers

    /// Runs the `kill` command with the specified signal.
    /// - Parameters:
    ///   - pid: The process ID to signal.
    ///   - signal: The signal name (e.g., "TERM", "KILL").
    /// - Returns: `true` if the command exited successfully (status 0), `false` otherwise.
    private func runKillCommand(pid: Int, signal: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: killPath)
        process.arguments = ["-\(signal)", "\(pid)"]
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    /// Checks whether a process with the given PID still exists.
    ///
    /// Uses `kill -0 <pid>` which sends no signal but checks if the process
    /// exists and the caller has permission to signal it.
    /// - Parameter pid: The process ID to check.
    /// - Returns: `true` if the process exists, `false` otherwise.
    private func processExists(pid: Int) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: killPath)
        process.arguments = ["-0", "\(pid)"]
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    /// Attempts to kill a process using administrator privileges via `osascript`.
    ///
    /// This displays a system password dialog to the user. If the user authorizes,
    /// `kill -9 <pid>` is executed as root.
    /// - Parameter pid: The process ID to terminate.
    /// - Returns: The result of the privileged kill operation.
    private func killWithAdminPrivileges(pid: Int) async -> KillResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let pipe = Pipe()

                // Construct the osascript command to run kill with admin privileges.
                let script = "do shell script \"/bin/kill -9 \(pid)\" with administrator privileges"

                process.executableURL = URL(fileURLWithPath: self.osascriptPath)
                process.arguments = ["-e", script]
                process.standardOutput = pipe
                process.standardError = pipe

                do {
                    try process.run()
                    process.waitUntilExit()

                    if process.terminationStatus == 0 {
                        // Verify the process is actually gone.
                        if self.processExists(pid: pid) {
                            continuation.resume(returning: .failed("进程仍然存在，终止失败。"))
                        } else {
                            continuation.resume(returning: .success)
                        }
                    } else {
                        let errorData = pipe.fileHandleForReading.readDataToEndOfFile()
                        let errorMessage = String(data: errorData, encoding: .utf8) ?? "未知错误"

                        // Check if the user cancelled the authorization dialog.
                        if errorMessage.contains("User canceled")
                            || errorMessage.contains("cancelled")
                            || errorMessage.contains("canceled") {
                            continuation.resume(returning: .failed("用户取消了管理员授权。"))
                        } else {
                            continuation.resume(returning: .failed("提权终止失败：\(errorMessage)"))
                        }
                    }
                } catch {
                    continuation.resume(returning: .failed(error.localizedDescription))
                }
            }
        }
    }
}
