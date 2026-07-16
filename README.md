# KillPort

A macOS menu bar utility for finding and killing processes occupying specific network ports.

## Features

- **Menu Bar Resident** — Lives in your system menu bar, always one click away.
- **Port Lookup** — Enter a port number (1–65535) to instantly see which processes are using it.
- **Process Details** — Displays command name, PID, user, file descriptor, protocol, and connection state.
- **One-Click Kill** — Terminate any process directly from the panel, with graceful SIGTERM → forceful SIGKILL escalation.
- **Privilege Escalation** — Automatically prompts for administrator privileges when needed.
- **Auto-Refresh** — Results refresh automatically after killing a process.
- **Pure Menu Bar App** — No Dock icon, no main window (LSUIElement).
- **Dark Mode Support** — Adapts automatically to light/dark appearance.
- **Modern UI** — Card-based results, frosted glass effect, smooth animations.

## Requirements

- macOS 12.0 (Monterey) or later
- Swift Command Line Tools (Xcode not required)

## Building

### Using the build script

```bash
./Scripts/build.sh
```

This will:
1. Compile the Swift package in release mode (`swift build -c release`).
2. Create a `KillPort.app` bundle in the project root.
3. Ad-hoc code sign the bundle.

### Manual build

```bash
swift build -c release
```

Then manually create the `.app` bundle structure:

```
KillPort.app/
└── Contents/
    ├── MacOS/
    │   └── KillPort          # Compiled binary
    └── Resources/
        └── Info.plist         # App configuration
```

## Usage

1. Launch `KillPort.app`.
2. Click the antenna icon in the menu bar.
3. Type a port number (e.g., `3000`, `8080`, `5173`).
4. Click **查询** (or press Enter).
5. View all processes occupying that port.
6. Click the red ✕ button next to a process to terminate it.
7. Confirm the termination in the dialog.

**Right-click** the menu bar icon to access the context menu (About / Quit).

## How It Works

### Port Scanning

Uses the system `lsof` utility:

```bash
lsof -i :<port> -P -n
```

The `-P` flag prevents port-to-name conversion, and `-n` prevents IP-to-hostname resolution, ensuring fast and predictable output.

### Process Termination

Follows a graceful-to-forceful escalation strategy:

1. **SIGTERM** — Sends `kill <PID>` for graceful shutdown.
2. **SIGKILL** — If the process survives after 1 second, sends `kill -9 <PID>`.
3. **Admin Privileges** — If both fail (insufficient permissions), uses `osascript` to prompt for the user's password and retry with elevated privileges.

## Project Structure

```
MacOS-KillPort/
├── Package.swift                     # SPM package definition
├── Sources/
│   └── KillPort/
│       ├── KillPortApp.swift         # @main entry, AppDelegate, NSApplication setup
│       ├── StatusBarController.swift  # NSStatusItem + NSPopover management
│       ├── PortScanner.swift         # lsof wrapper, port query logic
│       ├── ProcessKiller.swift       # Process termination logic (SIGTERM → SIGKILL → admin)
│       ├── ContentView.swift         # SwiftUI main view (search + results + cards)
│       └── Models.swift              # Data models (PortProcess, KillResult, ScanState)
├── Resources/
│   └── Info.plist                    # App config (LSUIElement=true)
├── Scripts/
│   └── build.sh                      # Build + package script
├── .gitignore
└── README.md
```

## License

This project is for personal use.
