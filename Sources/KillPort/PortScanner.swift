import Foundation

// MARK: - Port Scan Error

/// Errors that can occur during port scanning.
enum PortScanError: LocalizedError {
    /// The provided port number is out of valid range (1-65535).
    case invalidPort
    /// The lsof command failed to execute.
    case lsofFailed(String)
    /// The lsof output could not be parsed.
    case parseFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidPort:
            return "端口号无效，请输入 1-65535 之间的数字。"
        case .lsofFailed(let message):
            return "查询失败：\(message)"
        case .parseFailed(let message):
            return "解析失败：\(message)"
        }
    }
}

// MARK: - Port Scanner

/// Scans for processes occupying a given network port using the `lsof` system utility.
///
/// This class wraps the `lsof +c 0 -i :<port> -P -n` command, executes it on a background
/// thread, and parses the output into `PortProcess` objects.
///
/// The `+c 0` argument tells lsof to print the full command name instead of
/// truncating the COMMAND column to the default 9-character width.
final class PortScanner: Sendable {

    /// The path to the lsof binary.
    private let lsofPath = "/usr/sbin/lsof"

    /// Scans for processes occupying the specified port.
    /// - Parameter port: The port number to scan (must be 1-65535).
    /// - Returns: An array of `PortProcess` objects representing processes using the port.
    /// - Throws: `PortScanError` if the port is invalid or lsof fails.
    func scan(port: Int) async throws -> [PortProcess] {
        guard port >= 1 && port <= 65535 else {
            throw PortScanError.invalidPort
        }

        let output = try await runLsof(port: port)

        // Split output into lines, filtering empty lines.
        let lines = output.split(separator: "\n", omittingEmptySubsequences: true)

        // lsof outputs a header line followed by data lines.
        // If only the header (or nothing), no processes are using the port.
        guard lines.count > 1 else {
            return []
        }

        // Skip the header line and parse each data line.
        var processes: [PortProcess] = []
        for line in lines.dropFirst() {
            if let process = parseLsofLine(String(line)) {
                processes.append(process)
            }
        }

        return processes
    }

    /// Runs the `lsof` command and returns its standard output.
    /// - Parameter port: The port number to query.
    /// - Returns: The raw lsof output as a string.
    /// - Throws: `PortScanError.lsofFailed` if execution fails.
    private func runLsof(port: Int) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()

                process.executableURL = URL(fileURLWithPath: self.lsofPath)
                process.arguments = ["+c", "0", "-i", ":\(port)", "-P", "-n"]
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe

                do {
                    try process.run()
                    process.waitUntilExit()

                    let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8) ?? ""

                    // lsof returns exit code 1 when no processes are found,
                    // which is not an actual error for our use case.
                    if process.terminationStatus == 0 || process.terminationStatus == 1 {
                        continuation.resume(returning: output)
                    } else {
                        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                        let stderr = String(data: stderrData, encoding: .utf8) ?? ""
                        continuation.resume(
                            throwing: PortScanError.lsofFailed(
                                stderr.isEmpty
                                    ? "lsof exited with status \(process.terminationStatus)"
                                    : stderr
                            )
                        )
                    }
                } catch {
                    continuation.resume(throwing: PortScanError.lsofFailed(error.localizedDescription))
                }
            }
        }
    }

    /// Parses a single line of lsof output into a `PortProcess`.
    ///
    /// The expected lsof output format (with `+c 0 -i` flags) is:
    /// ```
    /// COMMAND               PID   USER   FD   TYPE   DEVICE SIZE/OFF NODE NAME
    /// MHalo.CoreFx.VAdmin 12345  user   23u  IPv6  0x1234      0t0  TCP *:3000 (LISTEN)
    /// ```
    ///
    /// The `+c 0` argument prevents lsof from truncating the COMMAND column to
    /// its default width of 9 characters, ensuring long process names are fully
    /// captured.
    ///
    /// COMMAND and NAME fields may contain spaces. The PID is identified as the
    /// first all-numeric token after the COMMAND field.
    ///
    /// - Parameter line: A single line of lsof output (not the header).
    /// - Returns: A `PortProcess` if parsing succeeds, `nil` otherwise.
    func parseLsofLine(_ line: String) -> PortProcess? {
        let tokens = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)

        // We need at minimum: COMMAND, PID, USER, FD, TYPE, DEVICE, SIZE/OFF, NODE, NAME
        guard tokens.count >= 9 else { return nil }

        // Find the PID: the first all-numeric token at index >= 1.
        // (Index 0 is always part of COMMAND.)
        var pidIndex = -1
        for i in 1..<tokens.count {
            if !tokens[i].isEmpty && tokens[i].allSatisfy(\.isNumber) {
                pidIndex = i
                break
            }
        }

        guard pidIndex > 0 else { return nil }

        // COMMAND = all tokens before the PID, joined with spaces.
        let command = tokens[0..<pidIndex].joined(separator: " ")

        // Parse PID.
        guard let pid = Int(tokens[pidIndex]) else { return nil }

        // Ensure we have enough tokens after PID for all fixed columns:
        // USER, FD, TYPE, DEVICE, SIZE/OFF, NODE, and at least one for NAME.
        // That's 7 tokens after PID (indices pidIndex+1 through pidIndex+7),
        // plus at least 1 for NAME = 8 total from pidIndex.
        guard tokens.count >= pidIndex + 8 else { return nil }

        let user = tokens[pidIndex + 1]
        let fd = tokens[pidIndex + 2]
        let type = tokens[pidIndex + 3]
        // tokens[pidIndex + 4] = DEVICE (skipped)
        // tokens[pidIndex + 5] = SIZE/OFF (skipped)
        // tokens[pidIndex + 6] = NODE / protocol (e.g., "TCP", "UDP") (skipped)

        // NAME = everything from pidIndex+7 onwards, joined with spaces.
        // This includes the address and state, e.g., "*:3000 (LISTEN)".
        let nameStartIndex = pidIndex + 7
        let name = tokens[nameStartIndex...].joined(separator: " ")

        return PortProcess(
            command: command,
            pid: pid,
            user: user,
            fileDescriptor: fd,
            type: type,
            name: name
        )
    }
}
