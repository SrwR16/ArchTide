# Migrating to Nandoroid Shell from KDE or GNOME

Making the jump from a full desktop environment like KDE Plasma or GNOME to a standalone window manager like Hyprland can feel daunting. This guide will help you understand exactly what changes when you switch to Nandoroid Shell and how to set up your new environment seamlessly.

## Understanding the Shift

When you move to Nandoroid Shell, you are only replacing the "shell" portion of your desktop. This means your panels, notifications, and system controls are swapped out, but much of the underlying infrastructure you rely on remains exactly the same.

### What Nandoroid Will Replace

| Your Old Feature | Your New Nandoroid Equivalent |
| :--- | :--- |
| Top or bottom panel (taskbar) | The Dynamic Island and Status Bar |
| System tray | Integrated smoothly into the Status Bar |
| Notification center | The Notification Center panel |
| Quick settings or control center | The Quick Settings panel |
| App launcher or menu | The App Launcher paired with Spotlight Search |
| Volume and brightness popups | Custom on screen display (OSD) overlays |
| Lock screen | Hyprlock infused with Nandoroid customizations |
| Display settings | Built-in Display Settings for resolution, scale, and arrangement |
| Bluetooth and Wi-Fi settings | Built-in controls within the Quick Settings and main Settings panel |
| System monitor | A built-in System Monitor powered by dgop |

### What Nandoroid Does Not Replace

Nandoroid relies on standard Linux portals and your own choice of apps for these features:

| Feature | What You Need to Use |
| :--- | :--- |
| **File picker dialogs** | `xdg-desktop-portal-gtk` or your portal of choice |
| **Screen sharing dialogs** | `xdg-desktop-portal-hyprland` |
| **File manager** | Dolphin, Nautilus, Thunar, or any manager you prefer |
| **Text editor or IDE** | Your existing favorite editor |
| **GTK and Qt theming** | Matugen generates GTK CSS, but you might want `nwg-look` or `qt6ct` for fine tuning |
| **Authentication prompts** | Nandoroid includes its own Polkit agent |
| **Clipboard manager** | Built into Spotlight, utilizing `wl-clipboard` |
| **Screenshot tool** | Built-in functionality utilizing `grim` and `slurp` |

## Setting Up Your New Environment

### 1. Install Hyprland
If you have not already done so, install and configure Hyprland as your system compositor:

```bash
sudo pacman -S hyprland
```

Your `~/.config/hypr/hyprland.lua` should at least include your monitor setup, input settings, preferred window rules, and keybinds. You can safely keep your existing Hyprland configuration. The Nandoroid installer will create a separate `nandoroid.lua` file and source it, so your personal shortcuts are never overwritten.

### 2. Configure Desktop Portals
This step is crucial. Without the proper portals, fundamental features like screen sharing and file selection will fail. Install them using:

```bash
sudo pacman -S xdg-desktop-portal-hyprland xdg-desktop-portal-gtk
```

Make sure your Hyprland configuration starts the dbus environment properly:

```lua
hl.exec_cmd("sleep 1 && dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP")
```

After logging in, verify that the services are active:

```bash
systemctl --user status xdg-desktop-portal-hyprland
systemctl --user status xdg-desktop-portal-gtk
```

### 3. Install Nandoroid Shell
Run the installation script to get everything set up:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/na-ive/nandoroid-shell/main/install.sh)"
```

During the prompt, it is highly recommended to install the core dependencies, the required fonts, and the Nandoroid CLI tool. If you want the shell to automatically launch with Hyprland, say yes to the configuration injection step.

### 4. Get Familiar with the Nandoroid CLI
The old method of controlling the shell involved typing out long IPC commands. We highly encourage transitioning to the new, unified `nandoroid` CLI tool. It is much cleaner and faster.

| What You Want to Do | The Old Way | The New Way |
| :--- | :--- | :--- |
| **Toggle Launcher** | `qs -c nandoroid ipc call launcher toggle` | `nandoroid launcher` |
| **Toggle Dashboard** | `qs -c nandoroid ipc call dashboard toggle` | `nandoroid dashboard` |
| **Toggle Settings** | `qs -c nandoroid ipc call settings toggle` | `nandoroid settings` |
| **Reload Shell** | `quickshell -c nandoroid --reload` | `nandoroid reload` |
| **Set Wallpaper** | Done manually through the panel | `nandoroid wallpaper <file_path>` |

Note for Fish users: The old manual `nandoroid.fish` completions have been removed. Simply installing the new `nandoroid-cli` will provide native completions for Fish, Zsh, and Bash.

### 5. Update Your Keybinds
Because Nandoroid uses the CLI tool to manage its panels, you should bind these commands in your `hyprland.lua`. Here is a great starting point based on the default configuration:

```lua
-- Tapping Super opens Spotlight
hl.bind("SUPER + Super_L", hl.dsp.exec_cmd("nandoroid spotlight toggle"), { release = true })

-- Panel Toggles (via CLI)
hl.bind("SUPER + Space", hl.dsp.exec_cmd("nandoroid launcher toggle"))
hl.bind("SUPER + A", hl.dsp.exec_cmd("nandoroid notifications toggle"))
hl.bind("SUPER + N", hl.dsp.exec_cmd("nandoroid quicksettings toggle"))
hl.bind("SUPER + G", hl.dsp.exec_cmd("nandoroid quickactions toggle"))
hl.bind("SUPER + D", hl.dsp.exec_cmd("nandoroid dashboard toggle"))
hl.bind("SUPER + I", hl.dsp.exec_cmd("nandoroid settings toggle"))
hl.bind("SUPER + Tab", hl.dsp.exec_cmd("nandoroid overview toggle"))
hl.bind("SUPER + L", hl.dsp.exec_cmd("nandoroid lock activate"))
hl.bind("CTRL + ALT + Delete", hl.dsp.exec_cmd("nandoroid systemmonitor toggle"))

-- Smooth Brightness Controls
hl.bind("XF86MonBrightnessUp", hl.dsp.exec_cmd("nandoroid brightness increment"), { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("nandoroid brightness decrement"), { locked = true, repeating = true })
```

### 6. Quickshell Global Shortcuts
Certain features remain bound directly as native Quickshell global shortcuts. These should be placed in your `hyprland.lua` exactly like this:

```lua
-- Region Tools (Screenshots & Recording)
hl.bind("SUPER + SHIFT + S", hl.dsp.global("quickshell:regionScreenshot"))
hl.bind("SUPER + SHIFT + R", hl.dsp.global("quickshell:regionRecord"), { locked = true })
hl.bind("SUPER + SHIFT + X", hl.dsp.global("quickshell:regionOcr"))

-- Spotlight Specifics
hl.bind("SUPER + Period", hl.dsp.global("quickshell:spotlightEmoji"), { description = "Emoji >> clipboard" })
hl.bind("SUPER + V", hl.dsp.global("quickshell:spotlightClipboard"), { description = "Clipboard history >> clipboard" })
```

If you ever need the raw IPC commands, they are fully documented in the main README.

## Advice for KDE Plasma Migrants

If you are coming directly from KDE Plasma on Wayland:
1. Make sure to remove any KDE autostart entries that might conflict, such as `plasmashell` or `kwin`.
2. Keep `qt6ct` installed if you rely on it for Qt application theming. Matugen will generate color schemes that play nicely alongside it.
3. Dolphin will continue to work perfectly as your main file manager.
4. KDE Connect operates independently and will keep functioning as expected.

## Advice for GNOME Migrants

If you are coming from GNOME:
1. You must switch your portal setup. Remove `xdg-desktop-portal-gnome` and replace it with `xdg-desktop-portal-gtk`. The GTK portal plays very nicely with Hyprland, while the GNOME one generally causes issues.
2. Nautilus (Files) will still work as your primary file manager.
3. Keep in mind that GNOME extensions will no longer apply. Nandoroid Shell provides all the equivalent shell features natively.

## Updating Safely

When an update for Nandoroid drops, your personal configurations are always kept safe. You do not even need to use the terminal to update. Simply open **Nandoroid Settings**, navigate to the **About** section, and use the built in **Shell Update** feature. From there, you can choose to update just the shell or everything at once.

If you prefer the terminal, running `update.sh all` or `update.sh shell` works exactly the same. Whichever method you choose, your personal Hyprland keybinds, terminal settings, and custom scripts are completely ignored and will never be overwritten.

## Troubleshooting Migration Issues

**Tip: Run a Dependency Check**
Before diving into manual troubleshooting, check the **Onboarding Panel** (which opens automatically on first launch) or go to **Nandoroid Settings > About > Dependency Check**. This will instantly highlight if your system is missing any crucial packages required for the shell to function properly.

If your dependencies are completely met but you still face hiccups, here are some common migration solutions:

| Symptom | The Likely Cause | How to Fix It |
| :--- | :--- | :--- |
| No file picker appears when saving | A missing GTK portal | Install and enable `xdg-desktop-portal-gtk` |
| Screen sharing only shows a black screen | A missing Hyprland portal | Install and enable `xdg-desktop-portal-hyprland` |
| Your old KDE panel is still showing up | Plasma is still running in the background | Remove `plasmashell` from your autostart entries |
| GTK apps look completely unstyled | No GTK theme has been applied | Matugen should auto-generate your GTK CSS, but you can also use `nwg-look` to force a theme |
| The terminal context menu does not open | The required terminal is missing | Make sure `kitty` is installed, as it is the default terminal |
| Icons are missing throughout the shell | The correct font is not installed | Install `ttf-material-symbols-variable-git` from the AUR |
| Your clipboard history is empty | `cliphist` is not running | Ensure `cliphist` is installed and running as a background daemon |
| The avatar picker refuses to open | `zenity` is missing | Install the `zenity` package |
