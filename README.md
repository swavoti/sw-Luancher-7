# SW Launcher 7

A lightweight, bloat-free Android home screen launcher built with Flutter and Material 3. It natively extracts dynamic colors from your active wallpaper using the Monet color system to give your device a cohesive, clean look.

![SW Launcher 7 Preview](https://raw.githubusercontent.com/swavoti/sw-Luancher-7/refs/heads/main/Screenshot_20260925-135043%20(1).png)

## Download

You can download the latest APK from the [Releases page on GitHub](https://github.com/swavoti/sw-Luancher-7/releases).

## Features

- **Monet Dynamic Themes:** Automatically extracts key colors from your current wallpaper and applies a complete Material 3 palette across the entire launcher.
- **Native Widget Support:** Add, resize, and manage essential system and third-party Android widgets seamlessly via Platform Views.
- **Workspace Management:** Interactive animated overview mode to easily manage, add, or remove multiple home screen pages.
- **Icon Customization:** Built-in tools to seamlessly rename apps and swap out individual app icons directly from your home screen.
- **Integrated Wallpaper Engine:** Browse, preview, and set curated, high-quality home and lock screen wallpapers without leaving the app.
- **Discover News Feed:** Swipe right from your main home screen to access a beautifully integrated daily news feed.
- **Live Weather Dashboard:** Built-in weather page to quickly check current conditions and local forecasts.
- **Fast App Drawer:** Ultra-fast, lazy-loaded app drawer with rapid searching and instant access to all installed applications.
- **Zero Bloatware:** Minimal RAM usage, extremely light on battery, and stripped down to only what a launcher actually needs.

## Known Limitations

### Android 10+ Gesture Navigation Issues
If you experience lag, flashing screens, or choppiness when swiping up to go home on Android 10+, **this is a known Android OS limitation, not a bug in SW Launcher 7.** 

Starting in Android 10, Google integrated the gesture and multitasking engine directly into the stock manufacturer launcher (QuickStep). Because Google has not released a public API for third-party launchers to use this engine, custom launchers cannot flawlessly handle the swipe-up home gesture.

**Solutions:**
1. **Switch to 3-button navigation** in your Android settings (Recommended for maximum stability).
2. **Root your device** and use third-party modules to force system gestures to route to the custom launcher (Not recommended for most users).
3. **Accept the animation jank** when swiping home.
## Tech Stack

| Component | Technology |
| :--- | :--- |
| **Framework** | Flutter |
| **Language** | Dart |
| **Design System** | Material 3 (Material You / Monet) |
| **Platform** | Android (API 21+) |

## Getting Started

### Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) (`v3.19.0` or higher recommended)
- Android Studio / VS Code / Zed / any IDE with Flutter support
- JDK 17

### Installation & Setup

1. Clone the repository:
   ```bash
   git clone [https://github.com/swavoti/sw-Luancher-7.git](https://github.com/swavoti/sw-Luancher-7.git)
   cd sw-Luancher-7
