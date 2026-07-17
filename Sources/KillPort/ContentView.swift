import SwiftUI

// MARK: - Notification Names

extension Notification.Name {
    /// popover 内容高度变化时发送此通知，用于动态调整 NSPopover 的 contentSize。
    static let popoverContentHeightChanged = Notification.Name("KillPortPopoverContentHeightChanged")
}

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

    /// 自动扫描结果（打开面板时扫描最近端口）。
    @Published private(set) var autoScanResults: [PortScanResult] = []

    /// 是否正在自动扫描最近端口。
    @Published private(set) var isAutoScanning: Bool = false

    // MARK: - Private Properties

    private let scanner = PortScanner()
    private let killer = ProcessKiller()

    /// The port number from the last successful scan, used for refresh after kill
    /// and for displaying the port number in the no-results view.
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

    /// The port number from the last scan, as a string for display.
    /// Used in `noResultsView` since `portInput` is cleared after scanning.
    var scannedPortLabel: String? {
        lastScannedPort.map { "\($0)" }
    }

    // MARK: - Actions

    /// Validates the port input and triggers a scan.
    ///
    /// On success, clears the input field and returns the scanned port number.
    /// On validation failure, sets the error state and returns nil.
    ///
    /// - Returns: The scanned port number, or nil if validation failed.
    @discardableResult
    func scanPort() -> Int? {
        // Filter and validate the port input.
        let trimmed = portInput.trimmingCharacters(in: .whitespaces)
        guard let port = Int(trimmed), port >= 1, port <= 65535 else {
            scanState = .error("请输入有效的端口号（1-65535）")
            return nil
        }

        portInput = ""  // 清空输入框
        scanSpecificPort(port)
        return port
    }

    /// Scans a specific port number without relying on `portInput`.
    ///
    /// Used by tag clicks and `scanPort()` internally.
    /// Sets the loading state and performs an async scan.
    ///
    /// - Parameter port: The port number to scan (1-65535).
    func scanSpecificPort(_ port: Int) {
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

    /// Resets the view model to auto-scan mode.
    ///
    /// Called when the popover is about to show, so that the auto-scan results
    /// are displayed instead of stale manual search results.
    func prepareForAutoScan() {
        scanState = .idle
    }

    /// Auto-scans all recent ports, collecting processes for ports that are in use.
    ///
    /// Scans all ports concurrently, then sorts results by the original
    /// `recentPorts` order (most recent first). Only ports with active
    /// processes are included in the results.
    ///
    /// - Parameter recentPorts: The list of recently queried ports to scan.
    func triggerAutoScan(recentPorts: [Int]) {
        guard !recentPorts.isEmpty else {
            autoScanResults = []
            return
        }
        isAutoScanning = true
        Task {
            var results: [PortScanResult] = []
            // 并发扫描所有端口
            await withTaskGroup(of: (Int, [PortProcess]).self) { group in
                for port in recentPorts {
                    group.addTask { [scanner] in
                        do {
                            let procs = try await scanner.scan(port: port)
                            return (port, procs)
                        } catch {
                            return (port, [])
                        }
                    }
                }
                for await (port, procs) in group {
                    if !procs.isEmpty {
                        results.append(PortScanResult(port: port, processes: procs))
                    }
                }
            }
            // 按 recentPorts 的原始顺序排序（最新查询在前）
            results.sort { a, b in
                let aIdx = recentPorts.firstIndex(of: a.port) ?? Int.max
                let bIdx = recentPorts.firstIndex(of: b.port) ?? Int.max
                return aIdx < bIdx
            }
            self.autoScanResults = results
            self.isAutoScanning = false
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
                // Refresh the scan to show updated results (silent, no loading state).
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

    /// Refreshes the scan results for the given port silently (without showing loading state).
    ///
    /// Used after a kill operation to update the results without flickering
    /// the loading indicator.
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
/// - A header with the app name, icon, and settings gear.
/// - A search bar with a port number input and query button.
/// - A recent ports tag bar (shown when there are saved ports).
/// - A scrollable results area showing process cards.
/// - Auto-scan results when the popover opens.
/// - States for loading, error, empty, and no results.
/// - A kill confirmation dialog.
struct ContentView: View {

    @StateObject private var viewModel = PortViewModel()
    @ObservedObject var settings: AppSettings

    /// Tracks which process cards are currently expanded (by process ID).
    @State private var expandedProcessIDs: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView

            Divider()

            // Search bar
            searchBar

            // 最近端口标签栏（有记录时才显示）
            if !settings.recentPorts.isEmpty {
                Divider()
                recentPortsBar
            }

            Divider()

            // Kill message banner (transient)
            if let message = viewModel.killMessage {
                killMessageBanner(message: message)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            // Content area
            contentArea
        }
        .frame(width: 380, height: computedPopoverHeight)
        .background(Color.clear)
        .animation(.easeInOut(duration: 0.25), value: viewModel.killMessage)
        .animation(.easeInOut(duration: 0.25), value: viewModel.scanState)
        .animation(.easeInOut(duration: 0.2), value: expandedProcessIDs)
        .onReceive(NotificationCenter.default.publisher(for: .popoverWillShow)) { _ in
            // 打开面板时重置到自动扫描模式并扫描最近端口
            viewModel.prepareForAutoScan()
            viewModel.triggerAutoScan(recentPorts: settings.recentPorts)
            expandedProcessIDs.removeAll()
        }
        .onChange(of: computedPopoverHeight) { newHeight in
            // 通知 StatusBarController 动态调整 popover 高度
            NotificationCenter.default.post(
                name: .popoverContentHeightChanged,
                object: nil,
                userInfo: ["height": newHeight]
            )
        }
        .onAppear {
            // 首次出现时也发送当前高度
            NotificationCenter.default.post(
                name: .popoverContentHeightChanged,
                object: nil,
                userInfo: ["height": computedPopoverHeight]
            )
        }
        .confirmationDialog(
            "确认终止进程",
            isPresented: Binding(
                get: { viewModel.killTarget != nil },
                set: { if !$0 { viewModel.cancelKill() } }
            ),
            titleVisibility: .visible,
            presenting: viewModel.killTarget
        ) { process in
            Button("终止 \(process.command) (PID: \(String(process.pid)))", role: .destructive) {
                viewModel.executeKill()
            }
            Button("取消", role: .cancel) {
                viewModel.cancelKill()
            }
        } message: { process in
            Text("确定要终止进程 \(process.command) (PID: \(String(process.pid))) 吗？\n此操作将先尝试优雅终止，失败后强制终止。")
        }
    }

    // MARK: - Popover Height Computation

    /// Computes the ideal popover height based on current content state.
    ///
    /// Used to dynamically resize the NSPopover to fit content without
    /// unnecessary scrolling. The height accounts for the header, search bar,
    /// recent ports bar, kill message banner, and the content area.
    private var computedPopoverHeight: CGFloat {
        var height: CGFloat = 0
        height += 50   // Header (padding 20 + content ~30)
        height += 1    // Divider
        height += 50   // Search bar (padding 20 + content ~30)
        if !settings.recentPorts.isEmpty {
            height += 1    // Divider
            height += 30   // Recent ports bar (padding 12 + content ~18)
        }
        height += 1    // Divider
        if viewModel.killMessage != nil {
            height += 40   // Kill message banner
        }
        height += contentAreaHeight
        return max(height, 200)
    }

    /// Computes the height of the content area based on the current view state.
    ///
    /// For empty/loading/error states, a fixed height of 130 is used.
    /// For results, the height is estimated based on the number of cards
    /// (and expanded cards), capped at a maximum to enable scrolling.
    private var contentAreaHeight: CGFloat {
        if viewModel.hasSearched {
            switch viewModel.scanState {
            case .loading:
                return 130
            case .error:
                return 140
            case .empty:
                return 130
            case .idle:
                return 130
            case .loaded(let processes):
                let expandedCount = processes.filter { expandedProcessIDs.contains($0.id) }.count
                return scrollableContentHeight(
                    cardCount: processes.count,
                    expandedCount: expandedCount
                )
            }
        } else if viewModel.isAutoScanning {
            return 130
        } else if !viewModel.autoScanResults.isEmpty {
            let totalCards = viewModel.autoScanResults.reduce(0) { $0 + $1.processes.count }
            let groupCount = viewModel.autoScanResults.count
            let allProcesses = viewModel.autoScanResults.flatMap { $0.processes }
            let expandedCount = allProcesses.filter { expandedProcessIDs.contains($0.id) }.count
            return scrollableContentHeight(
                cardCount: totalCards,
                groupHeaders: groupCount,
                expandedCount: expandedCount
            )
        } else {
            return 130
        }
    }

    /// Estimates the height of a scrollable results area.
    ///
    /// - Parameters:
    ///   - cardCount: Number of process cards.
    ///   - groupHeaders: Number of port group headers (for auto-scan results).
    ///   - expandedCount: Number of cards currently expanded (showing details).
    /// - Returns: Estimated height, capped at 350 to enable scrolling for many results.
    private func scrollableContentHeight(
        cardCount: Int,
        groupHeaders: Int = 0,
        expandedCount: Int = 0
    ) -> CGFloat {
        if cardCount == 0 { return 0 }
        let cardHeight: CGFloat = 58
        let expandedExtraHeight: CGFloat = 95
        let cardSpacing: CGFloat = 10
        let headerHeight: CGFloat = 24
        let headerSpacing: CGFloat = 6
        let groupSpacing: CGFloat = 10
        let padding: CGFloat = 32  // 16 top + 16 bottom

        var height = padding
        if groupHeaders > 0 {
            height += CGFloat(groupHeaders) * (headerHeight + headerSpacing)
            height += CGFloat(max(0, groupHeaders - 1)) * groupSpacing
        }
        height += CGFloat(cardCount) * cardHeight
        height += CGFloat(expandedCount) * expandedExtraHeight
        height += CGFloat(max(0, cardCount - 1)) * cardSpacing

        return min(height, 350)
    }

    // MARK: - Header

    /// Reads the app marketing version from the bundle's Info.plist.
    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.1.1"
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

            // 设置按钮
            Button(action: { showSettings() }) {
                Image(systemName: "gearshape")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("设置")

            Text("v" + appVersion)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
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
                    if let port = viewModel.scanPort() {
                        settings.addRecentPort(port)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .glassBackground(in: RoundedRectangle(cornerRadius: 8))

            Button(action: {
                if let port = viewModel.scanPort() {
                    settings.addRecentPort(port)
                }
            }) {
                Text("查询")
                    .font(.callout)
                    .fontWeight(.medium)
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isLoading || viewModel.portInput.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Recent Ports Bar

    private var recentPortsBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Text("最近")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                ForEach(settings.recentPorts, id: \.self) { port in
                    RecentPortTag(port: port) {
                        // 点击标签 → 查询
                        settings.addRecentPort(port)  // 移到最前
                        viewModel.scanSpecificPort(port)
                    } onDelete: {
                        settings.removeRecentPort(port)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
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
        .glassBackground(in: RoundedRectangle(cornerRadius: 8))
        .foregroundStyle(
            viewModel.killMessageIsError ? Color.red : Color.green
        )
    }

    // MARK: - Content Area

    @ViewBuilder
    private var contentArea: some View {
        if viewModel.hasSearched {
            // 用户已手动查询 → 显示查询结果
            switch viewModel.scanState {
            case .loading:
                loadingView
            case .error(let message):
                errorView(message: message)
            case .empty:
                noResultsView
            case .loaded:
                resultsScrollView
            case .idle:
                emptyStateView
            }
        } else if viewModel.isAutoScanning {
            // 正在自动扫描最近端口
            autoScanningView
        } else if !viewModel.autoScanResults.isEmpty {
            // 自动扫描完成，有结果 → 显示在用端口列表
            autoScanResultsView
        } else {
            // 空闲状态
            emptyStateView
        }
    }

    // MARK: - State Views

    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Image(systemName: "network.slash")
                .font(.system(size: 32))
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
        VStack(spacing: 8) {
            ProgressView()
                .scaleEffect(1.2)
            Text("正在查询...")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 28))
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
        VStack(spacing: 8) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 32))
                .foregroundStyle(.green)

            Text("没有进程占用此端口")
                .font(.callout)
                .foregroundStyle(.secondary)

            if let port = viewModel.scannedPortLabel {
                Text("端口 " + port + " 是空闲的")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Auto Scan Views

    private var autoScanningView: some View {
        VStack(spacing: 8) {
            ProgressView()
                .scaleEffect(1.1)
            Text("正在检查最近端口...")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var autoScanResultsView: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 10) {
                ForEach(viewModel.autoScanResults) { result in
                    VStack(alignment: .leading, spacing: 6) {
                        // 端口号标题
                        HStack(spacing: 4) {
                            Image(systemName: "circle.fill")
                                .font(.system(size: 6))
                                .foregroundStyle(.green)
                            Text("端口 " + String(result.port))
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 4)

                        // 进程卡片
                        ForEach(result.processes) { process in
                            ProcessCardView(
                                process: process,
                                isExpanded: expandedProcessIDs.contains(process.id),
                                onToggleExpand: { toggleExpand(process.id) },
                                onKill: { viewModel.requestKill(process) }
                            )
                        }
                    }
                }
            }
            .padding(16)
        }
    }

    // MARK: - Results

    private var resultsScrollView: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 10) {
                ForEach(viewModel.processes) { process in
                    ProcessCardView(
                        process: process,
                        isExpanded: expandedProcessIDs.contains(process.id),
                        onToggleExpand: { toggleExpand(process.id) },
                        onKill: { viewModel.requestKill(process) }
                    )
                }
            }
            .padding(16)
        }
    }

    // MARK: - Expand/Collapse Helper

    /// Toggles the expansion state of a process card.
    /// - Parameter id: The process ID (from `PortProcess.id`).
    private func toggleExpand(_ id: String) {
        withAnimation(.easeInOut(duration: 0.2)) {
            if expandedProcessIDs.contains(id) {
                expandedProcessIDs.remove(id)
            } else {
                expandedProcessIDs.insert(id)
            }
        }
    }

    // MARK: - Settings

    /// Sends a notification to open the settings window.
    private func showSettings() {
        NotificationCenter.default.post(name: .openSettings, object: nil)
    }
}

// MARK: - Recent Port Tag

/// A tag/chip displaying a recently queried port number.
///
/// - Tap: Triggers `onClick` to scan the port.
/// - Hover: Shows a delete button (×) that triggers `onDelete`.
struct RecentPortTag: View {
    let port: Int
    let onClick: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 3) {
            // Use String(port) to avoid LocalizedStringKey locale formatting
            // (e.g., "5,801" with thousands separator in some locales).
            Text(String(port))
                .font(.caption2)
                .fontWeight(.medium)

            if isHovered {
                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            isHovered
                ? Color.accentColor.opacity(0.2)
                : Color.accentColor.opacity(0.1)
        )
        .clipShape(Capsule())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .onTapGesture {
            onClick()
        }
        .help("点击查询端口 " + String(port))
    }
}

// MARK: - Process Card View

/// A card displaying a single process's information with a kill button.
///
/// In collapsed mode (default), only the process name and kill button are shown.
/// Tapping the chevron expands the card to reveal PID, user, FD, connection type,
/// and connection address details.
struct ProcessCardView: View {

    let process: PortProcess
    let isExpanded: Bool
    let onToggleExpand: () -> Void
    let onKill: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Collapsed content (always visible)
            HStack(alignment: .center, spacing: 12) {
                // Process icon
                Image(systemName: "terminal")
                    .font(.title3)
                    .foregroundStyle(.tint)
                    .frame(width: 28, height: 28)
                    .background(Color.accentColor.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                // Process name (truncated to single line when collapsed)
                Text(process.command)
                    .font(.callout)
                    .fontWeight(.semibold)
                    .lineLimit(isExpanded ? 2 : 1)
                    .truncationMode(.middle)
                    .help(process.command)

                Spacer(minLength: 4)

                // Expand/collapse chevron
                Button(action: onToggleExpand) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(isExpanded ? "收起详情" : "展开详情")

                // Kill button
                Button(action: onKill) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .help("终止此进程")
            }

            // Expanded details (conditionally visible)
            if isExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    Divider()
                        .padding(.vertical, 2)

                    infoRow(label: "PID", value: String(process.pid))
                    infoRow(label: "用户", value: process.user)
                    infoRow(label: "FD", value: process.fileDescriptor)

                    HStack(spacing: 6) {
                        Text(process.type)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.15))
                            .clipShape(Capsule())

                        Text(process.name)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 2)
                }
                .padding(.top, 8)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(12)
        .glassBackground(in: RoundedRectangle(cornerRadius: 10))
    }

    /// A labeled info row displaying a key-value pair.
    private func infoRow(label: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.tertiary)
            Text(":")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
