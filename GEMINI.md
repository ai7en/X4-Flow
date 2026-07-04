# AI Development Guidelines & System Context for X4 Flow 🌊

This document serves as the system prompt and architectural source of truth for AI agents (like Gemini) working on the **X4 Flow** project within Firebase Studio / Project IDX. It outlines the codebase structure, strict constraints, and module logic to prevent regression and compilation errors.

---

## 1. Environment & Workspace Context

* **IDE Environment:** Project IDX / Firebase Studio (Code OSS based).
* **Framework:** Flutter (Stable channel), Dart with strict Null Safety.
* **Target Platforms:** Android (Smartphones acting as a companion for ESP32 hardware).
* **Entry Point:** `lib/main.dart`
* **Configuration:** `.idx/dev.nix` handles system packages (`pkgs.flutter`, `pkgs.dart`).

---

## 2. Project Architecture & Core Modules

The application is a companion app for E-Ink e-readers (**Xteink X4** and **Xteink X3**) running on ESP32 microcontrollers. It features 5 primary tabs managed via an `IndexedStack` in `main.dart`:

1. **Books Converter (`lib/converter_screen.dart`, `lib/fb2_to_epub.dart`, `lib/epub_optimizer.dart`)**
   * Converts local `.fb2` files to valid `.epub` structures.
   * Uses `EpubOptimizer` to parse the OPF manifest, process images into grayscale, resize them to target screen resolutions, and package them using the `archive` library.
   * Handles footnotes seamlessly without breaking layout.

2. **Wallpaper Generator (`lib/wallpaper_screen.dart`, `lib/quote_templates.dart`, `lib/calendar_templates.dart`)**
   * **Photo Mode:** Custom image cropping, rotation, brightness/contrast adjustments, and Floyd-Steinberg Dithering to support low bit-depth E-Ink screens.
   * **Quote Mode:** Renders local literary quotes using predefined design themes (`quoteBackgrounds`). Supports English and Russian datasets (`quotes_en.dart`, `quotes_ru.dart`).
   * **Calendar Mode:** Draws a calendar grid onto a native canvas for the current month.

3. **Font Compiler (`lib/font_converter_screen.dart`, `lib/native_font_converter.dart`)**
   * Compiles standard desktop fonts into custom binary `.cpfont` files for CrossPoint firmware.
   * Bundles **4 distinct sub-styles** (Regular, Bold, Italic, BoldItalic) inside a single file payload.
   * Supports packing character ranges (ASCII, Cyrillic, Latin) and encodes bitmaps into a **2-Bit (4 levels of gray)** matrix for text anti-aliasing on E-Ink displays.

4. **Firmware Manager (`lib/firmware_screen.dart`)**
   * Connects to GitHub Releases API using `Dio` to fetch compiled ecosystem OTA binaries (`.bin`).
   * Monitored repositories: `uxjulia/CrossInk`, `obijuankenobiii/inx`, `crosspoint-reader/crosspoint-reader`, `franssjz/cpr-vcodex`, `alrudimgn/cpr-vcodex-fork`, `dawsonfi/papyrix-reader`.
   * Requires optional GitHub Token storage in `SharedPreferences`.

5. **Wi-Fi Web Panel (`lib/transfer_screen.dart`)**
   * Hosts an embedded `WebViewController` pointed at `http://crosspoint.local` or a user-defined IP address to manage wireless book delivery to the device.

---

## 3. 🛑 CRITICAL CODING RULES & CONSTRAINTS

When writing or modifying code for this project, the AI **MUST NOT** violate these design boundaries:

### Rule 3.1: Avoid FontStyle Name Collisions
* **Context:** The custom font compiler operates with an enum for the 4 styles. 
* **The Error:** A bare `enum FontStyle` collides with Flutter's built-in `ui.FontStyle` (which only supports `normal` and `italic`).
* **The Fix:** The custom font enum must be named **`CpFontStyle`** inside `lib/native_font_converter.dart`:
  ```dart
  enum CpFontStyle { regular, bold, italic, boldItalic }
  When building text rendering widgets or previews, explicitly map CpFontStyle to ui.FontStyle and FontWeight:
  fontStyle: (style == CpFontStyle.italic || style == CpFontStyle.boldItalic) 
    ? ui.FontStyle.italic 
    : ui.FontStyle.normal,
fontWeight: (style == CpFontStyle.bold || style == CpFontStyle.boldItalic) 
    ? FontWeight.bold 
    : FontWeight.normal,
    Rule 3.2: E-Ink Target Dimensions
Never hardcode screen layout dimensions or aspect ratios for image optimization/canvas painting. Always query the model-specific configurations defined in lib/device_profile.dart:

Xteink X4: 480 × 800 pixels (DeviceModel.x4)

Xteink X3: 528 × 792 pixels (DeviceModel.x3)

Rule 3.3: Localization Framework
Do not use standard BuildContext or .arb generation files. The project relies on a lightweight internal localization class (lib/app_localizations.dart).

When adding UI text elements, provide strings for both 'ru' and 'en' in the _localizedValues map inside app_localizations.dart and display them using:
AppLocalizations.of(context).translate('your_localization_key')
Rule 3.4: Asynchronous Operations and Mounted Checks
When handling operations inside screens (e.g., downloading firmware in firmware_screen.dart or waiting for files in converter_screen.dart), always verify state freshness if calling setState or modifying context after an await block:
if (!mounted) return;
setState(() { ... });
Rule 3.5: Git Conflicts Resolution Instruction
If a push rejection error occurs (! [rejected] main -> main (fetch first)), it indicates that remote changes exist. Instruct the user to synchronize upstream tracking branches cleanly via rebase:
git pull --rebase
4. Firebase MCP Server Configuration
When configuring or managing backend bindings inside Project IDX / Firebase Studio, apply the following setup inside .idx/mcp.json without altering other keys:
{
    "mcpServers": {
        "firebase": {
            "command": "npx",
            "args": [
                "-y",
                "firebase-tools@latest",
                "experimental:mcp"
            ]
        }
    }
}
