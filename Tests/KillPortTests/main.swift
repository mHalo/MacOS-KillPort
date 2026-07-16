import Foundation
import AppKit
import SwiftUI

// Include all source files directly by compiling them together.
// This file provides the test runner entry point.
// Source files: Models.swift, PortScanner.swift, ProcessKiller.swift,
//               StatusBarController.swift, ContentView.swift
// (KillPortApp.swift is excluded since it has @main)

// MARK: - Test Framework (Minimal)

/// A minimal test framework that replaces XCTest when only Command Line Tools are available.
final class TestRunner {
    private var passed = 0
    private var failed = 0
    private var failures: [String] = []
    private var currentTest = ""

    func run(_ name: String, _ block: () throws -> Void) {
        currentTest = name
        do {
            try block()
            passed += 1
            print("  ✅ \(name)")
        } catch {
            failed += 1
            failures.append("\(name): \(error)")
            print("  ❌ \(name) — \(error)")
        }
    }

    func runAsync(_ name: String, _ block: () async throws -> Void) async {
        currentTest = name
        do {
            try await block()
            passed += 1
            print("  ✅ \(name)")
        } catch {
            failed += 1
            failures.append("\(name): \(error)")
            print("  ❌ \(name) — \(error)")
        }
    }

    func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String = "") throws {
        if actual != expected {
            throw TestError.assertionFailed("Expected \(expected), got \(actual). \(message)")
        }
    }

    func assertNotNil(_ value: Any?, _ message: String = "") throws {
        if value == nil {
            throw TestError.assertionFailed("Expected non-nil value. \(message)")
        }
    }

    func assertNil(_ value: Any?, _ message: String = "") throws {
        if value != nil {
            throw TestError.assertionFailed("Expected nil, got \(String(describing: value)). \(message)")
        }
    }

    func assertTrue(_ condition: Bool, _ message: String = "") throws {
        if !condition {
            throw TestError.assertionFailed("Expected true. \(message)")
        }
    }

    func assertFalse(_ condition: Bool, _ message: String = "") throws {
        if condition {
            throw TestError.assertionFailed("Expected false. \(message)")
        }
    }

    func report() -> Int {
        print("")
        print("========================================")
        print("  Test Results: \(passed) passed, \(failed) failed")
        if !failures.isEmpty {
            print("")
            print("  Failures:")
            for f in failures {
                print("    - \(f)")
            }
        }
        print("========================================")
        return failed > 0 ? 1 : 0
    }
}

enum TestError: Error, CustomStringConvertible {
    case assertionFailed(String)

    var description: String {
        switch self {
        case .assertionFailed(let msg): return msg
        }
    }
}

// MARK: - Port Scanner Parsing Tests

func testPortScannerParsing(_ t: TestRunner) {
    let scanner = PortScanner()

    // Standard TCP listener (from real lsof output)
    t.run("testParseStandardLsofLine") {
        let line = "python3.1 13306 harlan    6u  IPv6 0xe8c99c0c0f2d0e4d      0t0  TCP *:18923 (LISTEN)"
        let result = scanner.parseLsofLine(line)
        try t.assertNotNil(result)
        try t.assertEqual(result?.command, "python3.1")
        try t.assertEqual(result?.pid, 13306)
        try t.assertEqual(result?.user, "harlan")
        try t.assertEqual(result?.fileDescriptor, "6u")
        try t.assertEqual(result?.type, "IPv6")
        try t.assertEqual(result?.name, "*:18923 (LISTEN)")
    }

    // IPv4 TCP listener
    t.run("testParseIPv4Line") {
        let line = "node    12345 user   23u  IPv4  0x1234abcd      0t0  TCP 127.0.0.1:3000 (LISTEN)"
        let result = scanner.parseLsofLine(line)
        try t.assertNotNil(result)
        try t.assertEqual(result?.command, "node")
        try t.assertEqual(result?.pid, 12345)
        try t.assertEqual(result?.user, "user")
        try t.assertEqual(result?.fileDescriptor, "23u")
        try t.assertEqual(result?.type, "IPv4")
        // Note: "TCP" is in the NODE column, not NAME. Parser correctly skips it.
        try t.assertEqual(result?.name, "127.0.0.1:3000 (LISTEN)")
    }

    // UDP connection
    t.run("testParseUDPLine") {
        let line = "dnsmasq  456 root    5u  IPv4  0xabcdef      0t0  UDP *:53"
        let result = scanner.parseLsofLine(line)
        try t.assertNotNil(result)
        try t.assertEqual(result?.command, "dnsmasq")
        try t.assertEqual(result?.pid, 456)
        try t.assertEqual(result?.user, "root")
        try t.assertEqual(result?.fileDescriptor, "5u")
        try t.assertEqual(result?.type, "IPv4")
        // Note: "UDP" is in the NODE column, not NAME. Parser correctly skips it.
        try t.assertEqual(result?.name, "*:53")
    }

    // Command with spaces
    t.run("testParseCommandWithSpaces") {
        let line = "Google Chrome Helper  9999  user   20u  IPv4  0xabc  0t0  TCP *:8080 (LISTEN)"
        let result = scanner.parseLsofLine(line)
        try t.assertNotNil(result, "Command with spaces should parse correctly")
        try t.assertEqual(result?.command, "Google Chrome Helper")
        try t.assertEqual(result?.pid, 9999)
    }

    // Established connection with remote address
    t.run("testParseEstablishedConnection") {
        let line = "ssh  7890 user   8u  IPv4  0x123  0t0  TCP 192.168.1.5:54321->10.0.0.1:22 (ESTABLISHED)"
        let result = scanner.parseLsofLine(line)
        try t.assertNotNil(result)
        try t.assertEqual(result?.command, "ssh")
        try t.assertEqual(result?.pid, 7890)
        // Note: "TCP" is in the NODE column, not NAME. Parser correctly skips it.
        try t.assertEqual(result?.name, "192.168.1.5:54321->10.0.0.1:22 (ESTABLISHED)")
    }

    // Empty line
    t.run("testParseEmptyLine") {
        let result = scanner.parseLsofLine("")
        try t.assertNil(result, "Empty line should return nil")
    }

    // Header line should not parse
    t.run("testParseHeaderLine") {
        let header = "COMMAND   PID   USER   FD   TYPE   DEVICE SIZE/OFF NODE NAME"
        let result = scanner.parseLsofLine(header)
        try t.assertNil(result, "Header line should not parse as a process")
    }

    // Too few tokens
    t.run("testParseTooFewTokens") {
        let line = "node 12345 user 23u IPv6"
        let result = scanner.parseLsofLine(line)
        try t.assertNil(result, "Line with too few tokens should return nil")
    }

    // No numeric PID
    t.run("testParseNoNumericPid") {
        let line = "node abc user fd IPv4 device size node name"
        let result = scanner.parseLsofLine(line)
        try t.assertNil(result, "Line with no numeric PID should return nil")
    }
}

// MARK: - Port Validation Tests

func testPortValidation(_ t: TestRunner) async {
    let scanner = PortScanner()

    await t.runAsync("testScanInvalidPortZero") {
        do {
            _ = try await scanner.scan(port: 0)
            throw TestError.assertionFailed("Should throw for port 0")
        } catch PortScanError.invalidPort {
            // Expected
        } catch {
            throw TestError.assertionFailed("Should throw invalidPort, got: \(error)")
        }
    }

    await t.runAsync("testScanInvalidPortNegative") {
        do {
            _ = try await scanner.scan(port: -1)
            throw TestError.assertionFailed("Should throw for negative port")
        } catch PortScanError.invalidPort {
            // Expected
        } catch {
            throw TestError.assertionFailed("Should throw invalidPort, got: \(error)")
        }
    }

    await t.runAsync("testScanInvalidPortTooHigh") {
        do {
            _ = try await scanner.scan(port: 65536)
            throw TestError.assertionFailed("Should throw for port > 65535")
        } catch PortScanError.invalidPort {
            // Expected
        } catch {
            throw TestError.assertionFailed("Should throw invalidPort, got: \(error)")
        }
    }

    await t.runAsync("testScanValidBoundaryPort1") {
        do {
            _ = try await scanner.scan(port: 1)
        } catch PortScanError.invalidPort {
            throw TestError.assertionFailed("Port 1 should be valid")
        } catch {
            // Other errors acceptable
        }
    }

    await t.runAsync("testScanValidBoundaryPort65535") {
        do {
            _ = try await scanner.scan(port: 65535)
        } catch PortScanError.invalidPort {
            throw TestError.assertionFailed("Port 65535 should be valid")
        } catch {
            // Other errors acceptable
        }
    }

    await t.runAsync("testScanUnusedPort") {
        do {
            let result = try await scanner.scan(port: 59999)
            try t.assertTrue(result.isEmpty, "Unused port should return empty array")
        } catch {
            throw TestError.assertionFailed("Scanning unused port should not throw: \(error)")
        }
    }
}

// MARK: - Process Killer Tests

func testProcessKiller(_ t: TestRunner) async {
    let killer = ProcessKiller()

    await t.runAsync("testKillOwnedProcess") {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["30"]
        try process.run()

        let pid = Int(process.processIdentifier)
        try t.assertTrue(pid > 0, "Process should have a valid PID")
        try t.assertTrue(processExists(Int32(pid)), "Process should exist before kill")

        let result = await killer.kill(pid: pid)

        switch result {
        case .success:
            break
        case .needsPrivilege:
            throw TestError.assertionFailed("Should not need privilege to kill own process")
        case .failed(let message):
            throw TestError.assertionFailed("Killing own process should succeed: \(message)")
        }

        try t.assertFalse(processExists(Int32(pid)), "Process should not exist after kill")
    }

    await t.runAsync("testKillNonExistentPid") {
        let result = await killer.kill(pid: 999999)

        switch result {
        case .success:
            break // Expected: process already gone
        case .needsPrivilege:
            throw TestError.assertionFailed("Should not need privilege for non-existent process")
        case .failed:
            break // Also acceptable
        }
    }
}

// MARK: - Model Tests

func testModels(_ t: TestRunner) {
    t.run("testPortProcessIdentity") {
        let process = PortProcess(
            command: "node", pid: 12345, user: "user",
            fileDescriptor: "23u", type: "IPv6", name: "TCP *:3000 (LISTEN)"
        )
        try t.assertEqual(process.id, "12345_23u")
    }

    t.run("testPortProcessDisplayName") {
        let process = PortProcess(
            command: "python3", pid: 678, user: "root",
            fileDescriptor: "5u", type: "IPv4", name: "TCP *:80 (LISTEN)"
        )
        try t.assertEqual(process.displayName, "python3 (PID: 678)")
    }

    t.run("testPortProcessEquality") {
        let p1 = PortProcess(
            command: "node", pid: 100, user: "user", fileDescriptor: "10u",
            type: "IPv4", name: "TCP *:3000 (LISTEN)"
        )
        let p2 = PortProcess(
            command: "node", pid: 100, user: "user", fileDescriptor: "10u",
            type: "IPv4", name: "TCP *:3000 (LISTEN)"
        )
        let p3 = PortProcess(
            command: "node", pid: 100, user: "user", fileDescriptor: "11u",
            type: "IPv4", name: "TCP *:3000 (LISTEN)"
        )
        try t.assertTrue(p1 == p2, "Identical processes should be equal")
        try t.assertFalse(p1 == p3, "Different FD should make processes unequal")
    }

    t.run("testPortProcessHashable") {
        let p1 = PortProcess(
            command: "node", pid: 100, user: "u", fileDescriptor: "10u",
            type: "IPv4", name: "TCP *:3000 (LISTEN)"
        )
        let p2 = PortProcess(
            command: "node", pid: 100, user: "u", fileDescriptor: "10u",
            type: "IPv4", name: "TCP *:3000 (LISTEN)"
        )
        let set: Set<PortProcess> = [p1, p2]
        try t.assertEqual(set.count, 1, "Identical processes should hash to same value")
    }

    t.run("testKillResultPatternMatching") {
        if case .success = KillResult.success {} else {
            throw TestError.assertionFailed("Expected .success")
        }
        if case .needsPrivilege = KillResult.needsPrivilege {} else {
            throw TestError.assertionFailed("Expected .needsPrivilege")
        }
        if case .failed(let msg) = KillResult.failed("error") {
            try t.assertEqual(msg, "error")
        } else {
            throw TestError.assertionFailed("Expected .failed with message")
        }
    }

    t.run("testScanStateEquality") {
        try t.assertTrue(ScanState.idle == ScanState.idle)
        try t.assertTrue(ScanState.loading == ScanState.loading)
        try t.assertTrue(ScanState.empty == ScanState.empty)
        try t.assertTrue(ScanState.error("msg") == ScanState.error("msg"))
        try t.assertFalse(ScanState.error("a") == ScanState.error("b"))

        let proc = PortProcess(
            command: "node", pid: 1, user: "u", fileDescriptor: "1u",
            type: "IPv4", name: "TCP *:80 (LISTEN)"
        )
        try t.assertTrue(ScanState.loaded([proc]) == ScanState.loaded([proc]))
        try t.assertFalse(ScanState.loaded([proc]) == ScanState.empty)
    }
}

// MARK: - Real Port Scan Test

func testRealPortScan(_ t: TestRunner) async {
    let scanner = PortScanner()

    await t.runAsync("testScanRealPort") {
        // Use the HTTP server we started on port 18923
        do {
            let result = try await scanner.scan(port: 18923)
            try t.assertFalse(result.isEmpty, "Should find process on port 18923")
            if let first = result.first {
                try t.assertTrue(first.pid > 0, "PID should be positive")
                try t.assertFalse(first.command.isEmpty, "Command should not be empty")
                print("       Found: \(first.command) PID:\(first.pid) FD:\(first.fileDescriptor)")
            }
        } catch {
            throw TestError.assertionFailed("Scanning port 18923 should succeed: \(error)")
        }
    }
}

// MARK: - Helper

func processExists(_ pid: Int32) -> Bool {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/kill")
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

// MARK: - Main

// Note: KillPortApp.swift is excluded from this compilation because it has @main.
// This file provides the main entry point instead.
@main
struct TestMain {
    static func main() async {
        let t = TestRunner()

        print("")
        print("╔══════════════════════════════════════╗")
        print("║     KillPort QA Test Suite           ║")
        print("╚══════════════════════════════════════╝")
        print("")

        print("━━━ Port Scanner Parsing Tests ━━━")
        testPortScannerParsing(t)

        print("")
        print("━━━ Port Validation Tests ━━━")
        await testPortValidation(t)

        print("")
        print("━━━ Model Tests ━━━")
        testModels(t)

        print("")
        print("━━━ Real Port Scan Tests ━━━")
        await testRealPortScan(t)

        print("")
        print("━━━ Process Killer Tests ━━━")
        await testProcessKiller(t)

        let exitCode = t.report()
        exit(Int32(exitCode))
    }
}
