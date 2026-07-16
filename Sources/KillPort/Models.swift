import Foundation

// MARK: - Data Models

/// Represents a process occupying a network port, parsed from lsof output.
struct PortProcess: Identifiable, Equatable, Hashable, Sendable {
    /// Stable identifier based on PID and file descriptor.
    var id: String { "\(pid)_\(fileDescriptor)" }

    /// Process command name (e.g., "node", "docker").
    let command: String

    /// Process ID.
    let pid: Int

    /// User who owns the process.
    let user: String

    /// File descriptor (e.g., "23u", "cwd").
    let fileDescriptor: String

    /// Network type (e.g., "IPv4", "IPv6").
    let type: String

    /// Network name/protocol info (e.g., "TCP *:3000 (LISTEN)").
    let name: String

    /// A human-readable display name for the process.
    var displayName: String {
        "\(command) (PID: \(pid))"
    }
}

// MARK: - Kill Result

/// Represents the outcome of a process termination attempt.
enum KillResult: Sendable {
    /// The process was successfully terminated.
    case success
    /// Administrator privileges are required.
    case needsPrivilege
    /// The termination failed with an error message.
    case failed(String)
}

// MARK: - Scan State

/// Represents the current state of a port scan operation.
enum ScanState: Equatable {
    /// No scan has been performed yet.
    case idle
    /// A scan is in progress.
    case loading
    /// The scan completed successfully with results.
    case loaded([PortProcess])
    /// The scan completed with no results.
    case empty
    /// The scan failed with an error.
    case error(String)
}
