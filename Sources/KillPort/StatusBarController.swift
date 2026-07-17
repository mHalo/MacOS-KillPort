import AppKit
import SwiftUI

// MARK: - Status Bar Controller

/// Manages the system status bar item (menu bar icon) and the popover panel.
///
/// This controller is responsible for:
/// - Creating and displaying an `NSStatusItem` in the system menu bar.
/// - Handling left-click to toggle the popover panel.
/// - Handling right-click (or Control-click) to show a context menu with a Quit option.
/// - Hosting the SwiftUI `ContentView` inside an `NSPopover`.
final class StatusBarController: NSObject {

    /// The status bar item shown in the system menu bar.
    private var statusItem: NSStatusItem!

    /// The popover panel that appears when the status bar icon is clicked.
    private var popover: NSPopover!

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
        popover.contentSize = NSSize(width: 380, height: 320)
        popover.behavior = .transient // Close when clicking outside.

        // Host the SwiftUI ContentView inside an NSHostingController.
        // On macOS 26+, make the hosting view transparent so the popover's
        // Liquid Glass material shows through the SwiftUI content.
        let hostingController = NSHostingController(rootView: ContentView())
        if #available(macOS 26.0, *) {
            hostingController.view.wantsLayer = true
            hostingController.view.layer?.backgroundColor = .clear
        }
        popover.contentViewController = hostingController
    }

    // MARK: - Actions

    /// Handles clicks on the status bar icon.
    /// - Left-click: Toggles the popover panel.
    /// - Right-click / Control-click: Shows a context menu with a Quit option.
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

    /// Shows the right-click context menu with a Quit option.
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

        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.3"

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
}
