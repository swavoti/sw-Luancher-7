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

## Known Limitations & Patches

### Android 10+ Gesture Navigation

Starting in Android 10, Google baked the gesture navigation engine directly into the stock manufacturer launcher (QuickStep). Third-party launchers have no official API to integrate with this engine, which causes jank, flashing, and in some cases a full "snap-back" where the previous app rubber-bands back into view.

SW Launcher 7 has implemented the following patches to minimize these issues as much as possible:

**Snap-Back & Jank Patches (applied internally):**
- **GestureNavContract strip** — Android sends a hidden `GESTURE_NAV_CONTRACT_CALLBACK` extra inside the swipe-home intent and waits for an AIDL response we cannot provide. We now strip this extra before the system ever processes it, stopping the timeout that causes the snap-back.
- **GPU hardware layer caching** — The root view is pinned into GPU memory on every `onResume` and `onNewIntent`. The system sees a pre-rendered window immediately, passing the gesture hand-off check without requiring a layout pass.
- **Gesture vs. resume signal split** — The launcher distinguishes between a swipe-home gesture and a regular foreground resume. On a gesture, all Dart-side entrance animations are bypassed completely (any animation during a gesture hand-off blocks the main thread and triggers snap-back). On a normal resume, a subtle 200ms fade-in plays.
- **Pre-warmed Flutter engine** — The Dart VM is initialized at process start via `FlutterEngineCache`, not when the activity launches. This eliminates the engine cold-start latency that makes Flutter launchers harder to integrate with system gestures.
- **Deferred post-frame work** — Any platform channel calls (widget preloading etc.) are deferred to `addPostFrameCallback` so `initState` is completely idle when the system inspects the window.

**If you still experience issues:**
1. Switch to 3-button navigation in your Android settings (most stable option).
2. Root your device and use QuickSwitch modules (not recommended for most users).

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
