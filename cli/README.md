# FLOW-cli

The primary command-line interface for the **Flow Shell** ecosystem.

> [!NOTE]  
> **Status: v1.0.0 (Release)**  
> This CLI serves as the unified terminal interface for managing shell lifecycle, panels, styling, and system maintenance.

## Features

Flow CLI provides a modular Bash-based interface to replace complex IPC calls with intuitive commands.

### Shell Lifecycle & Panels

| Feature | Command | Description |
| :--- | :--- | :--- |
| **Run Shell** | `flow run` | Start the Flow Shell environment |
| **Reload** | `flow reload` | Send a reload signal to Quickshell |
| **Debug** | `flow debug` | Run shell in debug mode with verbose output |
| **Logs** | `flow logs` | Stream real-time Quickshell logs |
| **App Launcher** | `flow launcher` | Toggle the App Launcher panel |
| **Spotlight** | `flow spotlight` | Toggle Spotlight search |
| **Notifications** | `flow notifications` | Toggle Notification Center |
| **Quick Settings** | `flow quicksettings` | Toggle Quick Settings panel |
| **Quick Actions** | `flow quickactions` | Toggle Quick Actions HUD |
| **System Monitor** | `flow systemmonitor` | Toggle System Monitor |
| **Dashboard** | `flow dashboard` | Toggle the Dashboard |
| **Overview** | `flow overview` | Toggle the Overview panel |
| **Session** | `flow session` | Toggle the Session (Power) menu |

### Spotlight Modes

| Mode | Command | Description |
| :--- | :--- | :--- |
| **Files** | `flow spotlight files` | Open Spotlight in File search mode |
| **Apps** | `flow spotlight apps` | Open Spotlight in App launcher mode |
| **Commands** | `flow spotlight commands` | Open Spotlight in Quick Command mode |
| **Clipboard** | `flow spotlight clipboard` | Open Spotlight in Clipboard history mode |
| **Emoji** | `flow spotlight emoji` | Open Spotlight in Emoji picker mode |

### Region Tools (Screenshots & Recording)

| Action | Command | Description |
| :--- | :--- | :--- |
| **Screenshot** | `flow region screenshot` | Capture a selected screen region |
| **Visual Search** | `flow region search` | Perform a visual search from region |
| **OCR** | `flow region ocr` | Extract text from selected region |
| **QR Code Scan** | `flow region qrcode` | Scan QR code from selected region |
| **Record** | `flow region record` | Record selected region |
| **Record w/ Audio** | `flow region record-audio` | Record region with system audio |

### Styling & Theme

| Feature | Command | Description |
| :--- | :--- | :--- |
| **Wallpaper** | `flow wallpaper [desktop\|lock]` | Open the wallpaper selection panel |
| **Auto-Cycle** | `flow wallpaper cycle {on\|off}` | Toggle wallpaper auto-cycling |
| **Colorscheme** | `flow colorscheme` | Regenerate Material 3 colors from wallpaper |
| **Theme Mode** | `flow theme {dark\|light\|toggle}` | Switch between Dark and Light mode |

### System & Maintenance

| Action | Command | Description |
| :--- | :--- | :--- |
| **Status** | `flow status` | Show current shell and CLI status |
| **Doctor** | `flow doctor` | Check system health and dependencies |
| **Config** | `flow config edit` | Open `config.json` in your default editor |
| **Install Shell** | `flow install` | Full interactive Flow Shell setup |
| **Install Deps** | `flow install deps` | Install all required system dependencies |
| **Update Shell** | `flow update shell` | Update Flow Shell (Stable/Canary) |
| **Update CLI** | `flow update cli` | Update this CLI tool to the latest version |
| **Lock Screen** | `flow lock` | Secure the session using Flow Lock |
| **Pomodoro** | `flow pomodoro {start\|pause\|stop\|reset}` | Control the Pomodoro timer |
| **Brightness** | `flow brightness {up\|down}` | Adjust screen brightness |
| **Reboot** | `flow reboot` | Reboot the system |
| **Poweroff** | `flow poweroff` | Shut down the system |

## Installation

### Method 1: Quick Install (Recommended)

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/na-ive/flow-cli/main/install.sh)"
```

### Method 2: Manual Clone

```bash
git clone https://github.com/na-ive/flow-cli.git
cd flow-cli
./install.sh
```

## Dependencies

- **Bash**: Core execution.
- **Python 3**: JSON configuration management.
- **Git & Curl**: Updates and installation.
- **Quickshell & Matugen**: Required for shell runtime features.

---

_Part of the Flow Ecosystem._
