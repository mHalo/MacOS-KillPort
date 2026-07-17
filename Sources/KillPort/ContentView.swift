import SwiftUI

// MARK: - View Model

/// The view model driving the port scanning and process killing UI.
///
/// This class is `@MainActor`-isolated to ensure all `@Published` property
/// updates occur on the main thread, which is required by SwiftUI.
@MainActor
final class PortViewModel: ObservableObject {

    // MARK: - Published Properties

    /// The text entered in the port input field.
    @Published var portInput: String = ""

    /// The current scan state (idle, loading, loaded, empty, error).
    @Published private(set) var scanState: ScanState = .idle

    /// The process currently targeted for killing (drives the confirmation dialog).
    @Published var killTarget: PortProcess?

    /// A transient message shown after a kill operation (auto-dismisses).
    @Published var killMessage: String?
    @Published var killMessageIsError: Bool = false

    // MARK: - Private Properties

    private let scanner = PortScanner()
    private let killer = ProcessKiller()

    /// The port number from the last successful scan, used for refresh after kill.
    private var lastScannedPort: Int?

    // MARK: - Computed Properties

    /// Whether a scan is currently in progress.
    var isLoading: Bool {
        if case .loading = scanState { return true }
        return false
    }

    /// The list of processes from the last successful scan.
    var processes: [PortProcess] {
        if case .loaded(let list) = scanState { return list }
        return []
    }

    /// The error message from the last scan, if any.
    var errorMessage: String? {
        if case .error(let msg) = scanState { return msg }
        return nil
    }

    /// Whether a scan has been performed (not in idle state).
    var hasSearched: Bool {
        scanState != .idle
    }

    // MARK: - Actions

    /// Validates the port input and triggers a scan.
    func scanPort() {
        // Filter and validate the port input.
        let trimmed = portInput.trimmingCharacters(in: .whitespaces)
        guard let port = Int(trimmed), port >= 1, port <= 65535 else {
            scanState = .error("请输入有效的端口号（1-65535）")
            return
        }

        lastScannedPort = port
        scanState = .loading

        Task {
            do {
                let result = try await scanner.scan(port: port)
                if result.isEmpty {
                    self.scanState = .empty
                } else {
                    self.scanState = .loaded(result)
                }
            } catch {
                self.scanState = .error(error.localizedDescription)
            }
        }
    }

    /// Sets the kill target, which triggers the confirmation dialog.
    /// - Parameter process: The process to kill.
    func requestKill(_ process: PortProcess) {
        killTarget = process
    }

    /// Cancels the kill confirmation dialog.
    func cancelKill() {
        killTarget = nil
    }

    /// Executes the kill on the current kill target, then refreshes the scan.
    func executeKill() {
        guard let process = killTarget else { return }
        killTarget = nil

        let pid = process.pid
        let command = process.command

        Task {
            let result = await killer.kill(pid: pid)

            switch result {
            case .success:
                showKillMessage("进程 \(command) (PID: \(pid)) 已终止", isError: false)
                // Refresh the scan to show updated results.
                if let port = lastScannedPort {
                    refreshScan(port: port)
                }

            case .needsPrivilege:
                showKillMessage("需要管理员权限才能终止此进程", isError: true)

            case .failed(let message):
                showKillMessage("终止失败：\(message)", isError: true)
            }
        }
    }

    /// Filters the port input to only allow digits (max 5 characters).
    /// - Parameter newValue: The new input value.
    func sanitizePortInput(_ newValue: String) {
        let filtered = newValue.filter { $0.isNumber }
        portInput = String(filtered.prefix(5))
    }

    // MARK: - Private Helpers

    /// Refreshes the scan results for the given port without changing the loading state.
    private func refreshScan(port: Int) {
        Task {
            do {
                let result = try await scanner.scan(port: port)
                if result.isEmpty {
                    self.scanState = .empty
                } else {
                    self.scanState = .loaded(result)
                }
            } catch {
                // Silently ignore refresh errors; keep previous state.
            }
        }
    }

    /// Shows a transient kill message that auto-dismisses after 3 seconds.
    private func showKillMessage(_ message: String, isError: Bool) {
        killMessage = message
        killMessageIsError = isError

        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            killMessage = nil
        }
    }
}

// MARK: - Content View

/// The main SwiftUI view displayed inside the popover panel.
///
/// Contains:
/// - A header with the app name and icon.
/// - A search bar with a port number input and query button.
/// - A scrollable results area showing process cards.
/// - States for loading, error, empty, and no results.
/// - A kill confirmation dialog.
struct ContentView: View {

    @StateObject private var viewModel = PortViewModel()

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView

            Divider()

            // Search bar
            searchBar

            Divider()

            // Kill message banner (transient)
            if let message = viewModel.killMessage {
                killMessageBanner(message: message)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            // Content area
            contentArea
        }
        .frame(width: 380, height: 480)
        .background(Color(NSColor.windowBackgroundColor))
        .animation(.easeInOut(duration: 0.25), value: viewModel.killMessage)
        .animation(.easeInOut(duration: 0.25), value: viewModel.scanState)
        .confirmationDialog(
            "确认终止进程",
            isPresented: Binding(
                get: { viewModel.killTarget != nil },
                set: { if !$0 { viewModel.cancelKill() } }
            ),
            titleVisibility: .visible,
            presenting: viewModel.killTarget
        ) { process in
            Button("终止 \(process.command) (PID: \(process.pid))", role: .destructive) {
                viewModel.executeKill()
            }
            Button("取消", role: .cancel) {
                viewModel.cancelKill()
            }
        } message: { process in
            Text("确定要终止进程 \(process.command) (PID: \(process.pid)) 吗？\n此操作将先尝试优雅终止，失败后强制终止。")
        }
    }

    // MARK: - Header

    /// Reads the app marketing version from the bundle's Info.plist.
    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.1"
    }

    private var headerView: some View {
        HStack(spacing: 10) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.title2)
                .foregroundStyle(.tint)

            VStack(alignment: .leading, spacing: 2) {
                Text("KillPort")
                    .font(.headline)
                    .fontWeight(.semibold)
                Text("端口进程管理工具")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text("v\(appVersion)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextField("输入端口号...", text: Binding(
                    get: { viewModel.portInput },
                    set: { viewModel.sanitizePortInput($0) }
                ))
                .textFieldStyle(.plain)
                .font(.body)
                .onSubmit {
                    viewModel.scanPort()
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color(NSColor.textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.primary.opacity(0.12), lineWidth: 1)
            )

            Button(action: { viewModel.scanPort() }) {
                Text("查询")
                    .font(.callout)
                    .fontWeight(.medium)
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isLoading || viewModel.portInput.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Kill Message Banner

    private func killMessageBanner(message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: viewModel.killMessageIsError
                ? "exclamationmark.triangle.fill"
                : "checkmark.circle.fill"
            )
            .font(.callout)

            Text(message)
                .font(.caption)
                .lineLimit(2)

            Spacer()

            Button {
                viewModel.killMessage = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            (viewModel.killMessageIsError
                ? Color.red.opacity(0.1)
                : Color.green.opacity(0.1)
            )
        )
        .foregroundStyle(
            viewModel.killMessageIsError ? Color.red : Color.green
        )
    }

    // MARK: - Content Area

    @ViewBuilder
    private var contentArea: some View {
        switch viewModel.scanState {
        case .idle:
            emptyStateView

        case .loading:
            loadingView

        case .error(let message):
            errorView(message: message)

        case .empty:
            noResultsView

        case .loaded:
            resultsScrollView
        }
    }

    // MARK: - State Views

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "network.slash")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)

            Text("输入端口号查询占用进程")
                .font(.callout)
                .foregroundStyle(.secondary)

            Text("支持 1 - 65535 范围内的端口")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(1.2)
            Text("正在查询...")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36))
                .foregroundStyle(.red)

            Text("查询失败")
                .font(.callout)
                .fontWeight(.medium)
                .foregroundStyle(.red)

            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noResultsView: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 40))
                .foregroundStyle(.green)

            Text("没有进程占用此端口")
                .font(.callout)
                .foregroundStyle(.secondary)

            if !viewModel.portInput.isEmpty {
                Text("端口 \(viewModel.portInput) 是空闲的")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Results

    private var resultsScrollView: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(viewModel.processes) { process in
                    ProcessCardView(process: process) {
                        viewModel.requestKill(process)
                    }
                }
            }
            .padding(16)
        }
    }
}

// MARK: - Process Card View

/// A card displaying a single process's information with a kill button.
struct ProcessCardView: View {

    let process: PortProcess
    let onKill: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Process icon
            Image(systemName: "terminal")
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 28, height: 28)
                .background(Color.accentColor.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 6))

            // Process details
            VStack(alignment: .leading, spacing: 4) {
                // Allow long process names to wrap onto a second line instead of
                // being truncated. `minimumScaleFactor` first attempts to shrink the
                // font slightly before wrapping; `fixedSize(vertical: true)` lets the
                // text expand vertically so it is never clipped. A hover tooltip shows
                // the full command for anything still ellipsized at 2 lines.
                Text(process.command)
                    .font(.callout)
                    .fontWeight(.semibold)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .minimumScaleFactor(0.85)
                    .fixedSize(horizontal: false, vertical: true)
                    .help(process.command)

                infoRow(label: "PID", value: "\(process.pid)")
                infoRow(label: "用户", value: process.user)
                infoRow(label: "FD", value: process.fileDescriptor)

                HStack(spacing: 4) {
                    Text("\(process.type)")
                        .font(.caption2)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.accentColor.opacity(0.15))
                        .clipShape(Capsule())

                    Text(process.name)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .padding(.top, 2)
            }

            Spacer(minLength: 4)

            // Kill button
            Button(action: onKill) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .help("终止此进程")
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    /// A labeled info row displaying a key-value pair.
    private func infoRow(label: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text("\(label):")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
