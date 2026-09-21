<div align="center">

# CFSSH Client

### Your SSH. Anywhere.

> A modern SSH client for Android, designed for developers, administrators, technicians, and power users.

[![Android](https://img.shields.io/badge/Platform-Android-3DDC84?style=for-the-badge&logo=android&logoColor=white)](https://www.android.com/)
[![Flutter](https://img.shields.io/badge/Framework-Flutter-02569B?style=for-the-badge&logo=flutter&logoColor=white)](https://flutter.dev/)
[![Dart](https://img.shields.io/badge/Language-Dart-0175C2?style=for-the-badge&logo=dart&logoColor=white)](https://dart.dev/)
[![SSH](https://img.shields.io/badge/Protocol-SSH%202.0-4EAA25?style=for-the-badge&logo=terminal&logoColor=white)](https://www.openssh.com/)

---

</div>

## Why CFSSH?

**CFSSH Client** brings a desktop-class SSH management experience to your Android device. Managing remote infrastructure from a mobile device usually means fighting clunky touch controls, broken key combinations, and simplified terminal emulators.

CFSSH Client solves this by combining **secure server profile management**, a **high-performance ANSI/VT terminal**, and a **touch-optimized soft keyboard toolbar** designed specifically for real Linux terminal interactions.

Whether you need to restart a systemd service on the go, edit remote configuration files in `nano` or `vim`, or attach to a long-running `tmux` session, CFSSH Client gives you total control without needing a computer.

---

## Features

### 🔐 SSH Authentication
- **Flexible Auth**: Authenticate using Username + Password or SSH Private Keys (PEM / OpenSSH format).
- **Passphrase Support**: Encrypted private keys with passphrases fully supported.
- **State & Error Feedback**: Clear visual indicators for handshake stages and descriptive authentication error handling.

### 💻 Terminal
- **True PTY Engine**: Built on `xterm` and `dartssh2` for real-time, low-latency terminal rendering.
- **ANSI / VT Support**: Full support for 256 colors, text styling, dynamic window resize signals (`SIGWINCH`), and cursor positioning.
- **Interactive Shell**: Seamless interactive terminal sessions with full UTF-8 encoding support.

### ⌨️ Mobile Keyboard
- **Sticky Modifiers**: Single-tap `CTRL` and `ALT` modifier toggles that work natively with standard Android soft keyboards.
- **Instant Dispatch**: Key combinations execute instantly without IME composition delays or requiring `Enter`.
- **Dedicated Touch Toolbar**: Quick access to essential terminal keys:
  - `ESC` • `TAB` • `HOME` • `END` • `PAGE UP` • `PAGE DOWN` • `INSERT` • `DELETE`
  - Arrow Navigation Keys (`▲` `▼` `◀` `▶`)
  - Function Keys (`F1` – `F12`)
- **TUI Friendly**: Smooth execution of critical shortcuts like `CTRL+C`, `CTRL+D`, `CTRL+O`, `CTRL+X`, `CTRL+Z`.

### 🖥️ Server Profiles
- **Profile Manager**: Save and organize server details (Host, Port, Username, Auth Type, Key references).
- **Live Status Monitoring**: Automatic host connectivity checks with visual status indicators on your server list.
- **Quick Dashboard**: View recently accessed servers, active sessions, and connection history at a glance.

### 🔒 Security
- **Hardware-Backed Keyring**: Sensitive credentials (passwords, private keys, and passphrases) are encrypted and stored securely using Android's Keystore system via `flutter_secure_storage`.
- **Isolated Metadata**: Non-sensitive server profiles and history are safely stored in an isolated local `sqflite` database.
- **Zero Telemetry**: Your credentials and terminal traffic stay 100% local to your device. No third-party servers or telemetry.

---

## Built for Real SSH Sessions

CFSSH Client isn't just a simple input box—it sends raw terminal escape sequences directly to the remote SSH PTY, making it completely compatible with standard CLI and TUI tools.

| Category | Supported Tools & Workflows |
| :--- | :--- |
| **Shells** | `Bash`, `Zsh`, `Fish`, `Sh` |
| **Text Editors** | `Nano`, `Vim`, `Neovim`, `Micro`, `Emacs` |
| **Multiplexers** | `tmux`, `Byobu`, `screen` |
| **System Monitors** | `htop`, `btop`, `top`, `iotop`, `glances` |
| **File Managers & Viewers** | `Midnight Commander (mc)`, `nnn`, `ranger`, `less`, `more` |

```bash
# Example: Full interactive session in CFSSH Client
ssh admin@server.example.com
tmux attach -t production
htop
```

---

## Screenshots

<!-- Add screenshot here: Server Profiles / Dashboard -->
<!-- Add screenshot here: Add / Edit Server Profile -->
<!-- Add screenshot here: Interactive Terminal Session -->
<!-- Add screenshot here: Mobile Keyboard Toolbar in action -->

---

## Tech Stack & Architecture

- **Framework**: [Flutter](https://flutter.dev) (Dart)
- **SSH Protocol**: [`dartssh2`](https://pub.dev/packages/dartssh2)
- **Terminal Emulator**: [`xterm`](https://pub.dev/packages/xterm)
- **State Management**: [`flutter_riverpod`](https://pub.dev/packages/flutter_riverpod)
- **Database**: [`sqflite`](https://pub.dev/packages/sqflite)
- **Secure Storage**: [`flutter_secure_storage`](https://pub.dev/packages/flutter_secure_storage)

---

## Getting Started

### Prerequisites
- [Flutter SDK](https://docs.flutter.dev/get-started/install) (`>=3.13.4`)
- Android device or emulator running Android 7.0 (API level 24) or higher

### Installation & Run

1. Clone the repository:
   ```bash
   git clone https://github.com/your-username/cfssh_client.git
   cd cfssh_client
   ```

2. Install dependencies:
   ```bash
   flutter pub get
   ```

3. Connect your Android device and run the app:
   ```bash
   flutter run
   ```

---

<div align="center">

Crafted for mobile productivity and remote server administration.

</div>
