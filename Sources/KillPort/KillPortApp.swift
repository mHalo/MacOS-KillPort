import AppKit

// MARK: - Application Delegate

/// The application delegate responsible for setting up the status bar controller.
///
/// Since this is a menu bar-only app (LSUIElement = true), we use a manual
/// `NSApplication` lifecycle instead of the standard SwiftUI `App` protocol.
/// The entry point creates `NSApplication`, sets the activation policy to
/// `.accessory` (no Dock icon), and runs the event loop.
final class AppDelegate: NSObject, NSApplicationDelegate {

    /// Strong reference to the status bar controller; keeps it alive for the
    /// app's lifetime since `NSStatusBar.system.statusItem` does not retain it.
    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusBarController = StatusBarController()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Clean up: close the popover if it's open.
        statusBarController = nil
    }
}

// MARK: - Entry Point

/// The main entry point for the KillPort application.
///
/// Usage of `@main` with a static `main()` function allows us to manually
/// configure `NSApplication` without relying on `@NSApplicationMain` or the
/// SwiftUI `App` lifecycle, which is necessary for a pure menu bar app
/// without a full Xcode project.
@main
struct KillPortApp {

    static func main() {
        let app = NSApplication.shared

        // .accessory policy: no Dock icon, no app menu bar.
        app.setActivationPolicy(.accessory)

        let delegate = AppDelegate()
        app.delegate = delegate

        // Use withExtendedLifetime to guarantee the delegate is not
        // deallocated prematurely (NSApplication.delegate is weak).
        withExtendedLifetime(delegate) {
            app.run()
        }
    }
}
