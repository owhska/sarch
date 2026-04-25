## 🚀 Installation

### Quick Install
```bash
git clone https://https://github.com/owhska/files.git
cd files
chmod +x install.sh
chmod +x install-yay.sh
./install-yay.sh
./install.sh

```
## 📦 What It Installs

| Component             | Purpose                          |
|------------------------|----------------------------------|
| `i3`                  | Tiling window manager            |
| `sxhkd`               | Hotkey daemon                    |
| `picom` `(FT-Labs)`   | Compositor for transparency      |
| `i3-status`             | Status bar                       |
| `rofi`                | Application launcher             |
| `dunst`               | Notifications                    |
| `kitty`               | Terminal emulator (main)         |
| `st`                  | Simple terminal (scratchpad)     |
| `firefox-esr`         | Default web browser              |
| `thunar` + plugins    | File manager                     |
| `nala`                | Better apt frontend              |
| `pipewire`            | Audio handling                   |
| `flameshot`,          | Screenshot tools                 |
| `micro`               | Terminal text editor             |
| `redshift`            | Night light                      |
| `qimgv`               | Lightweight image viewer         |
| `fzf`, etc.           | Utilities & enhancements         |

---

## 🔑 Keybindings Overview

| Key Combo              | Action                                |
|------------------------|----------------------------------------|
| `Super + Enter`        | Launch terminal                        |
| `Super + Shift + Enter`| Toggle scratchpad terminal             |
| `Super + d`            | Launch rofi                            |
| `Super + Shift + q`    | Close focused window                   |
| `Super + H`            | Help via keybind viewer                |
| `Super + V`            | Audio mixer (pulsemixer) in scratchpad |
| `Super + Shift + R`    | Restart i3                             |
| `Super + 1-9,0`        | Switch to workspace 1-10               |
| `Super + Shift + 1-9,0`| Move window to workspace 1-10          |
| `Super + Minus`        | Move window to scratchpad              |
| `Super + Equal`        | Show/hide scratchpad                   |

Keybindings are configured via:

- `~/.config/i3/sxhkd/sxhkdrc`
- `~/.config/i3/scripts/help` (run manually or with `Super + Z`)

---

## 📂 Configuration Files

```
~/.config/i3/
├── config                 # Main i3 config
├── workspaces.conf        # Workspace definitions
├── rules.conf             # Window rules and appearance
├── sxhkd/
│   └── sxhkdrc            # Keybinding configuration
── dunst/
│   └── dunstrc
├── rofi/
│   ├── config.rasi
│   ├── keybinds.rasi
│   └── power.rasi
├── picom/
│   └── picom.conf
├── scripts/
│   ├── autostart.sh
│   ├── changevolume
│   ├── power
│   ├── scratchpad
│   └── help
├── wallpaper/
│   └── (wallpaper images)
```

**Advanced scratchpad usage:**
```bash
# Launch custom applications in scratchpad mode
Super + Shift + Enter    # Default terminal scratchpad
Super + V                # Pulsemixer scratchpad
# Or via script: scratchpad app_name app_command
```
--
