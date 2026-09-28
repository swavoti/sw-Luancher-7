# App Drawer Performance Findings

File analyzed: lib/screens/app_drawer.dart
Scope: swipe freeze + sluggishness when paging through the app drawer.
No files were modified. This is analysis only.

## Critical (prime freeze culprits)

### 1. Every app item is permanently keep-alive
Lines ~476-479: `_AppDrawerItemState` mixes in `AutomaticKeepAliveClientMixin` with `wantKeepAlive => true`.
- `PageView.builder` (line ~338) and `GridView.builder` (line ~353) are lazy and are supposed to recycle off-screen children. Forcing keep-alive defeats that.
- After swiping several pages, every item state plus its decoded icon bitmap stays resident forever.
- Memory and rebuild cost grow the more you swipe, producing progressive slowdown and eventual jank/freeze.
- GC pressure from retained `Uint8List` icon buffers spikes mid-swipe.
Fix direction: remove keep-alive (or gate it), let the lazy builders recycle.

### 2. Per-item platform-channel icon fetch (N+1 IPC storm)
Lines ~504-514: each item independently calls `InstalledApps.getAppInfo(widget.app.packageName)` when `app.icon == null`.
- If DB metadata lacks icons (common right after `syncAppsBackground` resolves), every visible item fires a separate async platform-channel round-trip to Android during the swipe.
- Swiping builds the next page, triggering dozens of simultaneous channel calls, each ending in `setState`.
Fix direction: batch icon loading, or ensure `prefetchIcons` fully populates icons into the in-memory cache before the grid renders so items never hit the channel.

## High impact

### 3. `setState` on every page change rebuilds the whole drawer
Lines ~340-344: `onPageChanged` calls `setState(() => _currentPage = page)`. That rebuilds `LayoutBuilder`, recomputes grid metrics, rebuilds the `PageView` and all visible page content, purely to move the page-indicator dots.
Fix direction: isolate the indicator into its own `AnimatedBuilder`/`ValueListenableBuilder` so page changes do not rebuild the grid.

### 4. Recomputing `sublist` per page build
Line ~351: `gridApps.sublist(start, end)` allocates a new list on every item build of the PageView. Minor, but compounds the churn above.
Fix direction: memoize per-page slices or compute them once.

### 5. `AutomaticKeepAliveClientMixin` + `LongPressDraggable` together
Each item is a `LongPressDraggable` (line ~624) wrapped in a keep-alive state. Long-press drag gesture arenas across many retained draggables make the gesture disambiguation heavier during a swipe, especially when a vertical swipe begins near an item that also wants a long-press.

## Medium impact

### 6. Frobbed image built inside a blur pass
Lines ~427-437: the frosted-glass background uses `ImageFiltered` with `ImageFilter.blur(sigmaX: 30, sigmaY: 30)` over a full-screen `Image.asset`. A sigma-30 blur of a full-res wallpaper on every frame is expensive and is re-created every rebuild (which, per finding 3, happens on every page change).
Fix direction: render the blur once (RepaintBoundary / cached layer), and make sure the wallpaper is not re-blurred on every rebuild.

### 7. `Image.asset(_savedWallpaperPath!)` decoded each time
Not sized or cached to the viewport; relies on the default asset cache but is reinserted into the tree on every rebuild.

### 8. Unbounded `List.generate` for page dots
Lines ~393-411: one `Container` per page is built eagerly inside the build method. For a device with hundreds of apps and few rows per page, `pages` can be very large (e.g. 50-100+ dots). This allocates a big dot row and adds layout cost on every rebuild.
Fix direction: cap / window the dot indicator or render a compact scrollable indicator.

## Low impact / notes

- `_loadSettings` (lines ~78-87) does three separate prefs reads but only once; negligible.
- Search filtering `_filterApps` (lines ~151-158) rebuilds the full grid on every keystroke; acceptable for the current list size but grows with app count.
- `prefetchIcons` is fire-and-forget; if it fails, the N+1 storm in finding 2 reasserts itself.

## Recommended priority order
1. Remove/gate `AutomaticKeepAliveClientMixin` keep-alive (finding 1).
2. Guarantee icons are cached before render so items never hit the platform channel mid-swipe (finding 2).
3. Stop rebuilding the whole drawer on page change (finding 3).
4. Cache the blurred wallpaper layer outside the rebuild path (finding 6).
5. Window/cap the page indicator (finding 8).

Download codetist codetist.swavoti.co.za