# 🌊 Flow

Flow is an independent project derived from ArchTide, which itself was derived from ii-vynx (vaguesyntax/ii-vynx), which itself is based on illogical-impulse (end-4/dots-hyprland). It provides a state-of-the-art Linux desktop experience adhering to Material 3 (Material You) design principles, featuring dynamic theming via Matugen and a highly modular architecture built on Quickshell.

---

## Overview

Flow provides a state-of-the-art Linux desktop experience adhering to **Material 3 (Material You)** design principles, featuring dynamic theming via Matugen and a highly modular architecture built on **Quickshell**.

> [!NOTE]
> This project is a work in progress. Some modules may require manual setup of API keys.

---

## Installation

### Default installation

Use this if you don't have illogical-impulse already installed. It sets up the base dotfiles and everything they need, then puts Flow's Quickshell config on top.

```bash
git clone --recurse-submodules https://github.com/SrwR16/ArchTide.git
cd ArchTide
./setup-flow.sh install
```

### Minimal installation (only quickshell config)

Use this if illogical-impulse is already working and you only want Flow's Quickshell config. Nothing else is touched, and your current config is moved to a backup rather than deleted.

```bash
git clone --recurse-submodules https://github.com/SrwR16/ArchTide.git
cd ArchTide
./setup-flow.sh
```

---

## Management CLI

After installation, the `flow` command is available at `~/.local/bin/flow`:

```bash
# Apply the Quickshell config (default)
flow apply

# Install base illogical-impulse, then apply
flow install

# Update Flow config from GitHub
flow update

# Restart Quickshell
flow restart

# Report resolved paths, state and tooling
flow doctor

# Show help
flow help

# Show version
flow version
```

---

## Upstream Attribution

Flow is built upon the work of these upstream projects:

- **[end-4/dots-hyprland](https://github.com/end-4/dots-hyprland)** — illogical-impulse (base dotfiles)
- **[vaguesyntax/ii-vynx](https://github.com/vaguesyntax/ii-vynx)** — ii-vynx (intermediate fork)
- **[Quickshell](https://quickshell.org/)** — Widget system
- **[Hyprland](https://hypr.land/)** — Compositor

See [NOTICE](NOTICE) for detailed attribution.

---

## License

GPL-3.0 — See [LICENSE](LICENSE) for details.

---

<div align="center">
    <p><b>If you like this project, consider giving it a star! ⭐</b></p>
</div>