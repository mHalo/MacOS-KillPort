import AppKit
import SwiftUI
import ServiceManagement

// MARK: - Status Bar Controller

/// Manages the system status bar item (menu bar icon) and the popover panel.
///
/// This controller is responsible for:
/// - Creating and displaying an `NSStatusItem` in the system menu bar.
/// - Handling left-click to toggle the popover panel.
/// - Handling right-click (or Control-click) to show a context menu with
///   About, Settings, and Quit options.
/// - Hosting the SwiftUI `ContentView` inside an `NSPopover`.
/// - Managing the settings window (opened from the gear icon or context menu).
/// - Handling launch-at-login registration via `SMAppService` (macOS 13+).
final class StatusBarController: NSObject {

    /// The status bar item shown in the system menu bar.
    private var statusItem: NSStatusItem!

    /// The popover panel that appears when the status bar icon is clicked.
    private var popover: NSPopover!

    /// Persistent application settings shared between ContentView and SettingsView.
    private let settings = AppSettings()

    /// The settings window, lazily created on first open.
    private var settingsWindow: NSWindow?

    // MARK: - Initialization

    override init() {
        super.init()

        // Create the status bar item with variable length (adapts to icon width).
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        // Configure the status bar button.
        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "antenna.radiowaves.left.and.right",
                accessibilityDescription: "KillPort"
            )
            button.image?.isTemplate = true // Adapt to light/dark mode automatically.
            button.action = #selector(statusItemClicked(_:))
            button.target = self
            // Receive events for both left and right mouse clicks.
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        // Create and configure the popover.
        popover = NSPopover()
        // Initial size; will be dynamically adjusted via popoverContentHeightChanged
        // notifications from ContentView based on actual content.
        popover.contentSize = NSSize(width: 380, height: 360)
        popover.behavior = .transient // Close when clicking outside.
        popover.delegate = self

        // Host the SwiftUI ContentView inside an NSHostingController.
        // On macOS 26+, make the hosting view transparent so the popover's
        // Liquid Glass material shows through the SwiftUI content.
        let hostingController = NSHostingController(rootView: ContentView(settings: settings))
        if #available(macOS 26.0, *) {
            hostingController.view.wantsLayer = true
            hostingController.view.layer?.backgroundColor = .clear
        }
        popover.contentViewController = hostingController

        // 监听设置面板打开请求
        NotificationCenter.default.addObserver(
            self, selector: #selector(showSettingsWindow),
            name: .openSettings, object: nil
        )

        // 监听开机启动设置变化
        NotificationCenter.default.addObserver(
            self, selector: #selector(launchAtLoginChanged(_:)),
            name: .launchAtLoginChanged, object: nil
        )

        // 监听 popover 内容高度变化，动态调整 popover 尺寸
        NotificationCenter.default.addObserver(
            self, selector: #selector(handlePopoverHeightChanged(_:)),
            name: .popoverContentHeightChanged, object: nil
        )

        // 如果设置了开机启动，确保已注册
        if settings.launchAtLogin {
            updateLaunchAtLogin(enabled: true)
        }
    }

    // MARK: - Actions

    /// Handles clicks on the status bar icon.
    /// - Left-click: Toggles the popover panel.
    /// - Right-click / Control-click: Shows a context menu with About, Settings, and Quit.
    @objc private func statusItemClicked(_ sender: AnyObject?) {
        guard let event = NSApp.currentEvent else {
            togglePopover()
            return
        }

        // Check for right-click or Control-click.
        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            showContextMenu()
        } else {
            togglePopover()
        }
    }

    /// Toggles the popover's visibility.
    private func togglePopover() {
        guard let button = statusItem.button else { return }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            // Activate the app so the popover receives keyboard focus.
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    /// Shows the right-click context menu with About, Settings, and Quit options.
    private func showContextMenu() {
        guard let button = statusItem.button else { return }

        let menu = NSMenu()

        let aboutItem = NSMenuItem(
            title: "关于 KillPort",
            action: #selector(showAbout),
            keyEquivalent: ""
        )
        aboutItem.target = self
        menu.addItem(aboutItem)

        let settingsItem = NSMenuItem(
            title: "设置...",
            action: #selector(showSettingsWindow),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(
            title: "退出 KillPort",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        // Position the menu below the status bar icon.
        let point = NSPoint(x: 0, y: button.bounds.height + 4)
        menu.popUp(positioning: nil, at: point, in: button)
    }

    /// Shows the about panel.
    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)

        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.1.1"

        NSApp.orderFrontStandardAboutPanel(
            options: [
                .applicationName: "KillPort",
                .applicationVersion: appVersion,
                .credits: NSAttributedString(
                    string: "macOS 菜单栏端口管理工具",
                    attributes: [.font: NSFont.systemFont(ofSize: 11)]
                )
            ]
        )
    }

    /// Terminates the application.
    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    // MARK: - Settings Window

    /// Shows the settings window as an independent NSWindow.
    @objc private func showSettingsWindow() {
        NSApp.activate(ignoringOtherApps: true)

        if settingsWindow == nil {
            let settingsView = SettingsView(settings: settings)
            let hostingController = NSHostingController(rootView: settingsView)
            // Make the content view transparent so the glass section cards
            // can blend with the desktop on macOS 26+.
            hostingController.view.wantsLayer = true
            if #available(macOS 26.0, *) {
                hostingController.view.layer?.backgroundColor = .clear
            }
            settingsWindow = NSWindow(contentViewController: hostingController)
            settingsWindow?.title = "KillPort 设置"
            settingsWindow?.styleMask = [.titled, .closable]
            settingsWindow?.isReleasedWhenClosed = false
            settingsWindow?.center()
        }

        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Launch at Login

    /// Handles launch-at-login setting changes via notification.
    @objc private func launchAtLoginChanged(_ notification: Notification) {
        guard let enabled = notification.userInfo?["enabled"] as? Bool else { return }
        updateLaunchAtLogin(enabled: enabled)
    }

    /// Handles popover content height changes by resizing the popover.
    ///
    /// Called when ContentView's `computedPopoverHeight` changes, allowing
    /// the popover to dynamically adapt its height to fit the content
    /// without unnecessary scrolling.
    @objc private func handlePopoverHeightChanged(_ notification: Notification) {
        guard let height = notification.userInfo?["height"] as? CGFloat else { return }
        let currentHeight = popover.contentSize.height
        // Only update if the height difference is significant (> 1pt) to
        // avoid unnecessary layout passes from minor floating-point changes.
        if abs(currentHeight - height) > 1 {
            popover.contentSize = NSSize(width: 380, height: height)
        }
    }

    /// Registers or unregisters the app for launch at login using SMAppService (macOS 13+).
    /// On macOS 12, this is a no-op since SMAppService.mainApp is unavailable.
    /// - Parameter enabled: True to register, false to unregister.
    private func updateLaunchAtLogin(enabled: Bool) {
        if #available(macOS 13.0, *) {
            let service = SMAppService.mainApp
            do {
                if enabled {
                    try service.register()
                } else {
                    try service.unregister()
                }
            } catch {
                print("Failed to \(enabled ? "register" : "unregister") launch at login: \(error)")
            }
        }
        // macOS 12 不支持 SMAppService.mainApp，跳过
    }
}

// MARK: - NSPopoverDelegate

extension StatusBarController: NSPopoverDelegate {
    /// Called when the popover is about to show. Posts a notification so
    /// ContentView can trigger an auto-scan of recent ports.
    func popoverWillShow(_ notification: Notification) {
        NotificationCenter.default.post(name: .popoverWillShow, object: nil)
    }
}
