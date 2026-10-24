import 'dart:async';
import 'dart:collection';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:swavoti/services/launcher_service.dart';
import 'package:swavoti/services/lightweight_mode.dart';

class LauncherItem {
  final String id;
  String type; // 'app', 'widget', 'folder', 'time_weather_widget', 'search_widget'
  String packageName;
  final String? className;
  final int? appWidgetId;
  int x;
  int y;
  int spanX;
  int spanY;
  int page;
  String label;
  List<String>? folderApps;

  LauncherItem({
    required this.id,
    required this.type,
    required this.packageName,
    this.className,
    this.appWidgetId,
    required this.x,
    required this.y,
    this.spanX = 1,
    this.spanY = 1,
    this.page = 0,
    required this.label,
    this.folderApps,
  });

  bool get isAnyWidget =>
      type == 'widget' ||
      type == 'time_weather_widget' ||
      type == 'search_widget';

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'packageName': packageName,
    'className': className,
    'appWidgetId': appWidgetId,
    'x': x,
    'y': y,
    'spanX': spanX,
    'spanY': spanY,
    'page': page,
    'label': label,
    if (folderApps != null) 'folderApps': folderApps,
  };

  factory LauncherItem.fromJson(Map<String, dynamic> json) => LauncherItem(
    id: json['id'] as String,
    type: json['type'] as String,
    packageName: json['packageName'] as String? ?? '',
    className: json['className'] as String?,
    appWidgetId: (json['appWidgetId'] as num?)?.toInt(),
    x: (json['x'] as num?)?.toInt() ?? 0,
    y: (json['y'] as num?)?.toInt() ?? 0,
    spanX: (json['spanX'] as num?)?.toInt() ?? 1,
    spanY: (json['spanY'] as num?)?.toInt() ?? 1,
    page: (json['page'] as num?)?.toInt() ?? 0,
    label: json['label'] as String? ?? '',
    folderApps: json['folderApps'] != null
        ? List<String>.from(json['folderApps'] as Iterable)
        : null,
  );
}

class WidgetCapabilities {
  final bool configurable;
  final bool resizeHorizontal;
  final bool resizeVertical;
  final int minWidthDp;
  final int minHeightDp;
  final int minResizeWidthDp;
  final int minResizeHeightDp;
  final int maxResizeWidthDp;
  final int maxResizeHeightDp;
  final int defaultSpanX;
  final int defaultSpanY;

  const WidgetCapabilities({
    this.configurable = false,
    this.resizeHorizontal = true,
    this.resizeVertical = true,
    this.minWidthDp = 40,
    this.minHeightDp = 40,
    this.minResizeWidthDp = 40,
    this.minResizeHeightDp = 40,
    this.maxResizeWidthDp = 0,
    this.maxResizeHeightDp = 0,
    this.defaultSpanX = 2,
    this.defaultSpanY = 2,
  });

  factory WidgetCapabilities.fromMap(Map<String, dynamic> map) {
    return WidgetCapabilities(
      configurable: map['configurable'] == true,
      resizeHorizontal: map['resizeHorizontal'] != false,
      resizeVertical: map['resizeVertical'] != false,
      minWidthDp: (map['minWidthDp'] as num?)?.toInt() ?? 40,
      minHeightDp: (map['minHeightDp'] as num?)?.toInt() ?? 40,
      minResizeWidthDp: (map['minResizeWidthDp'] as num?)?.toInt() ?? 40,
      minResizeHeightDp: (map['minResizeHeightDp'] as num?)?.toInt() ?? 40,
      maxResizeWidthDp: (map['maxResizeWidthDp'] as num?)?.toInt() ?? 0,
      maxResizeHeightDp: (map['maxResizeHeightDp'] as num?)?.toInt() ?? 0,
      defaultSpanX: ((map['defaultSpanX'] as num?)?.toInt() ?? 2).clamp(1, 4),
      defaultSpanY: ((map['defaultSpanY'] as num?)?.toInt() ?? 2).clamp(1, 5),
    );
  }
}

/// Deterministic byte-budgeted LRU buffer cache for widget previews & snapshots.
class _LruByteCache {
  final LinkedHashMap<String, Uint8List> _entries =
      LinkedHashMap<String, Uint8List>();
  int _currentBytes = 0;

  int get currentBytes => _currentBytes;

  int get maxBytes =>
      LightweightMode.isEnabled ? (3 * 1024 * 1024) : (6 * 1024 * 1024);

  Uint8List? get(String key) {
    final existing = _entries.remove(key);
    if (existing != null) {
      _entries[key] = existing;
    }
    return existing;
  }

  void put(String key, Uint8List bytes) {
    final limit = maxBytes;
    if (bytes.lengthInBytes > limit ~/ 2) {
      return;
    }
    final old = _entries.remove(key);
    if (old != null) {
      _currentBytes -= old.lengthInBytes;
    }
    while (_entries.isNotEmpty &&
        _currentBytes + bytes.lengthInBytes > limit) {
      final oldestKey = _entries.keys.first;
      final evicted = _entries.remove(oldestKey);
      if (evicted != null) {
        _currentBytes -= evicted.lengthInBytes;
      }
    }
    _entries[key] = bytes;
    _currentBytes += bytes.lengthInBytes;
  }

  void remove(String key) {
    final old = _entries.remove(key);
    if (old != null) {
      _currentBytes -= old.lengthInBytes;
    }
  }

  void trimToHalf() {
    final target = maxBytes ~/ 2;
    while (_entries.isNotEmpty && _currentBytes > target) {
      final oldestKey = _entries.keys.first;
      final evicted = _entries.remove(oldestKey);
      if (evicted != null) {
        _currentBytes -= evicted.lengthInBytes;
      }
    }
  }
}

/// Persistent background Dart Isolate that decodes, downscales, and re-encodes
/// widget preview and snapshot images off the main UI isolate to strictly cap RAM.
class WidgetMemoryIsolate {
  Isolate? _isolate;
  SendPort? _workerSendPort;
  ReceivePort? _mainReceivePort;
  Future<void>? _spawning;
  int _nextRequestId = 1;
  final Map<int, Completer<Uint8List?>> _pending =
      <int, Completer<Uint8List?>>{};
  Timer? _idleShutdownTimer;

  Future<void> _ensureRunning() {
    if (_workerSendPort != null) return Future<void>.value();
    if (_spawning != null) return _spawning!;
    final completer = Completer<void>();
    _spawning = completer.future;

    final receivePort = ReceivePort();
    _mainReceivePort = receivePort;

    receivePort.listen((dynamic message) {
      if (message is SendPort) {
        _workerSendPort = message;
        if (!completer.isCompleted) completer.complete();
        return;
      }
      if (message is List && message.length == 2) {
        final reqId = message[0] as int;
        final transferable = message[1] as TransferableTypedData?;
        final pendingCompleter = _pending.remove(reqId);
        if (pendingCompleter != null && !pendingCompleter.isCompleted) {
          pendingCompleter.complete(transferable?.materialize().asUint8List());
        }
        _scheduleIdleShutdown();
      }
    });

    Isolate.spawn<SendPort>(
      _widgetMemoryWorkerEntry,
      receivePort.sendPort,
      debugName: 'SwavotiWidgetRamIsolate',
    ).catchError((Object error) {
      _spawning = null;
      receivePort.close();
      if (!completer.isCompleted) completer.completeError(error);
      return Isolate.current;
    });

    return completer.future;
  }

  void _scheduleIdleShutdown() {
    _idleShutdownTimer?.cancel();
    if (_pending.isNotEmpty) return;
    // Shut down idle worker isolate after 20s of inactivity so the isolate
    // heap itself returns 100% of its memory back to the OS!
    _idleShutdownTimer = Timer(const Duration(seconds: 20), () {
      if (_pending.isEmpty) {
        dispose();
      }
    });
  }

  Future<Uint8List?> compressBytes(
    Uint8List source, {
    int maxWidth = 220,
    int maxHeight = 180,
  }) async {
    if (source.isEmpty) return null;
    if (source.lengthInBytes <= 10 * 1024) {
      return source;
    }
    try {
      await _ensureRunning();
      final sendPort = _workerSendPort;
      if (sendPort == null) return source;

      _idleShutdownTimer?.cancel();
      final requestId = _nextRequestId++;
      final completer = Completer<Uint8List?>();
      _pending[requestId] = completer;

      sendPort.send(<Object?>[
        requestId,
        TransferableTypedData.fromList(<Uint8List>[source]),
        maxWidth,
        maxHeight,
      ]);

      final result = await completer.future.timeout(
        const Duration(seconds: 4),
        onTimeout: () {
          _pending.remove(requestId);
          return source;
        },
      );
      return result ?? source;
    } catch (_) {
      return source;
    }
  }

  void dispose() {
    _idleShutdownTimer?.cancel();
    _idleShutdownTimer = null;
    _workerSendPort = null;
    _spawning = null;
    _mainReceivePort?.close();
    _mainReceivePort = null;
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    for (final c in _pending.values) {
      if (!c.isCompleted) c.complete(null);
    }
    _pending.clear();
  }

  static void _widgetMemoryWorkerEntry(SendPort mainSendPort) {
    final workerReceivePort = ReceivePort();
    mainSendPort.send(workerReceivePort.sendPort);

    workerReceivePort.listen((dynamic msg) {
      if (msg is! List || msg.length < 4) return;
      final reqId = msg[0] as int;
      final transferable = msg[1] as TransferableTypedData;
      final maxW = msg[2] as int;
      final maxH = msg[3] as int;

      final rawBytes = transferable.materialize().asUint8List();
      Uint8List output = rawBytes;
      try {
        final decoded = img.decodeImage(rawBytes);
        if (decoded != null) {
          img.Image target = decoded;
          if (decoded.width > maxW || decoded.height > maxH) {
            final scaleW = maxW / decoded.width;
            final scaleH = maxH / decoded.height;
            final scale = scaleW < scaleH ? scaleW : scaleH;
            final newW = (decoded.width * scale).round().clamp(1, maxW);
            final newH = (decoded.height * scale).round().clamp(1, maxH);
            target = img.copyResize(
              decoded,
              width: newW,
              height: newH,
              interpolation: img.Interpolation.average,
            );
          }
          final hasAlpha = target.numChannels == 4;
          final reencoded = hasAlpha
              ? Uint8List.fromList(img.encodePng(target, level: 6))
              : Uint8List.fromList(img.encodeJpg(target, quality: 78));
          if (reencoded.lengthInBytes < rawBytes.lengthInBytes ||
              !identical(target, decoded)) {
            output = reencoded;
          }
        }
      } catch (_) {
        output = rawBytes;
      }

      mainSendPort.send(<Object?>[
        reqId,
        TransferableTypedData.fromList(<Uint8List>[output]),
      ]);
    });
  }
}

/// Central controller for hosting Android AppWidgets, computing grid freedom
/// spans, dispatching live size updates, and enforcing Isolate RAM caps.
class WidgetHostController extends ChangeNotifier {
  WidgetHostController._();
  static final WidgetHostController instance = WidgetHostController._();

  final WidgetMemoryIsolate _memoryIsolate = WidgetMemoryIsolate();
  final _LruByteCache _byteCache = _LruByteCache();
  final Map<int, WidgetCapabilities> _capabilitiesCache =
      <int, WidgetCapabilities>{};
  final Map<int, (int, int)> _lastSentSizeDp = <int, (int, int)>{};
  final Map<int, Timer> _sizeDebounceTimers = <int, Timer>{};
  bool _catalogBudgetingInProgress = false;

  int get currentCachedBytes => _byteCache.currentBytes;

  void onMemoryPressure() {
    _byteCache.trimToHalf();
    _memoryIsolate.dispose();
  }

  /// Determines whether a widget on [itemPage] should mount a live AndroidView
  /// or hibernate into an Isolate-compressed snapshot to cap RAM.
  bool shouldMountLiveView({
    required int itemPage,
    required int currentPage,
  }) {
    final allowedDistance = LightweightMode.isEnabled ? 0 : 1;
    return (itemPage - currentPage).abs() <= allowedDistance;
  }

  Uint8List? getCachedSnapshot(int appWidgetId) {
    return _byteCache.get('snap:$appWidgetId');
  }

  Uint8List? getCachedPreview(String providerPackage, String providerClass) {
    return _byteCache.get('prev:$providerPackage/$providerClass');
  }

  /// Captures a snapshot of a live AndroidView and downscales it inside our
  /// background Dart Isolate before storing in the strict LRU byte budget.
  Future<Uint8List?> captureWidgetSnapshot(int appWidgetId) async {
    final raw = await LauncherService.captureWidgetSnapshot(
      appWidgetId,
      maxSidePx: LightweightMode.isEnabled ? 220 : 300,
    );
    if (raw == null || raw.isEmpty) {
      return getCachedSnapshot(appWidgetId);
    }
    final compressed = await _memoryIsolate.compressBytes(
      raw,
      maxWidth: LightweightMode.isEnabled ? 200 : 280,
      maxHeight: LightweightMode.isEnabled ? 200 : 280,
    );
    if (compressed != null && compressed.isNotEmpty) {
      _byteCache.put('snap:$appWidgetId', compressed);
      notifyListeners();
      return compressed;
    }
    return raw;
  }

  /// Loads widget catalog and compresses heavy preview images in the background
  /// Dart Isolate so the picker and home screen stay within the RAM budget.
  Future<List<Map<String, dynamic>>> getBudgetedCatalog() async {
    final widgets = await LauncherService.getAllWidgets();
    if (!_catalogBudgetingInProgress && widgets.isNotEmpty) {
      _catalogBudgetingInProgress = true;
      unawaited(_budgetCatalogPreviewsInBackground(widgets));
    }
    return widgets;
  }

  Future<void> _budgetCatalogPreviewsInBackground(
    List<Map<String, dynamic>> widgets,
  ) async {
    try {
      final updated = <Map<String, dynamic>>[];
      for (final w in widgets) {
        final copy = Map<String, dynamic>.from(w);
        final pkg = copy['providerPackage'] as String? ?? '';
        final cls = copy['providerClass'] as String? ?? '';
        final key = 'prev:$pkg/$cls';
        final cached = _byteCache.get(key);
        if (cached != null) {
          copy['preview'] = cached;
        } else {
          final raw = copy['preview'] as Uint8List?;
          if (raw != null && raw.isNotEmpty) {
            final compact = await _memoryIsolate.compressBytes(
              raw,
              maxWidth: 200,
              maxHeight: 150,
            );
            if (compact != null) {
              _byteCache.put(key, compact);
              copy['preview'] = compact;
            }
          }
        }
        updated.add(copy);
      }
      LauncherService.replaceCachedWidgets(updated);
    } finally {
      _catalogBudgetingInProgress = false;
    }
  }

  static (int, int) defaultSpanForWidgetData(
    Map<String, dynamic> widgetData, {
    required int columns,
    required int rows,
  }) {
    final rawX = (widgetData['defaultSpanX'] as num?)?.toInt() ??
        (widgetData['spanX'] as num?)?.toInt() ??
        2;
    final rawY = (widgetData['defaultSpanY'] as num?)?.toInt() ??
        (widgetData['spanY'] as num?)?.toInt() ??
        2;
    return (rawX.clamp(1, columns), rawY.clamp(1, rows));
  }

  Future<int?> allocateAndBindWidget(Map<String, dynamic> widgetData) async {
    final pkg = widgetData['providerPackage'] as String? ?? '';
    final cls = widgetData['providerClass'] as String? ?? '';
    if (pkg.isEmpty || cls.isEmpty) return null;

    final id = await LauncherService.allocateWidgetId();
    if (id == -1) return null;

    final bound = await LauncherService.bindWidget(id, pkg, cls);
    if (!bound) {
      await LauncherService.deleteWidgetId(id);
      return null;
    }
    return id;
  }

  Future<void> deleteWidget(int? appWidgetId) async {
    if (appWidgetId == null || appWidgetId == -1) return;
    _sizeDebounceTimers.remove(appWidgetId)?.cancel();
    _lastSentSizeDp.remove(appWidgetId);
    _capabilitiesCache.remove(appWidgetId);
    _byteCache.remove('snap:$appWidgetId');
    await LauncherService.deleteWidgetId(appWidgetId);
  }

  Future<WidgetCapabilities> getCapabilities(
    LauncherItem item, {
    required int columns,
  }) async {
    if (item.type == 'time_weather_widget') {
      return WidgetCapabilities(
        configurable: false,
        resizeHorizontal: true,
        resizeVertical: true,
        defaultSpanX: columns.clamp(1, 4),
        defaultSpanY: 1,
      );
    }
    if (item.type == 'search_widget') {
      return WidgetCapabilities(
        configurable: false,
        resizeHorizontal: true,
        resizeVertical: true,
        defaultSpanX: columns.clamp(1, 4),
        defaultSpanY: 1,
      );
    }
    final widgetId = item.appWidgetId;
    if (widgetId == null || widgetId == -1) {
      return const WidgetCapabilities();
    }
    final cached = _capabilitiesCache[widgetId];
    if (cached != null) return cached;

    final map = await LauncherService.widgetCapabilities(widgetId);
    final parsed = WidgetCapabilities.fromMap(map);
    _capabilitiesCache[widgetId] = parsed;
    return parsed;
  }

  void notifyWidgetSizeChanged(
    int appWidgetId, {
    required double widthDp,
    required double heightDp,
    bool immediate = false,
  }) {
    if (appWidgetId == -1 || widthDp <= 0 || heightDp <= 0) return;
    final w = widthDp.round().clamp(24, 2000);
    final h = heightDp.round().clamp(24, 2000);
    final prev = _lastSentSizeDp[appWidgetId];
    if (prev != null &&
        (prev.$1 - w).abs() < 2 &&
        (prev.$2 - h).abs() < 2 &&
        !immediate) {
      return;
    }

    _sizeDebounceTimers.remove(appWidgetId)?.cancel();
    if (immediate) {
      _lastSentSizeDp[appWidgetId] = (w, h);
      unawaited(
        LauncherService.updateWidgetSize(
          appWidgetId,
          minWidthDp: w,
          minHeightDp: h,
          maxWidthDp: w,
          maxHeightDp: h,
        ),
      );
      return;
    }

    _sizeDebounceTimers[appWidgetId] = Timer(
      const Duration(milliseconds: 36),
      () {
        _sizeDebounceTimers.remove(appWidgetId);
        _lastSentSizeDp[appWidgetId] = (w, h);
        unawaited(
          LauncherService.updateWidgetSize(
            appWidgetId,
            minWidthDp: w,
            minHeightDp: h,
            maxWidthDp: w,
            maxHeightDp: h,
          ),
        );
      },
    );
  }
}

/// 2D Grid placement & Lawnchair/Launcher3 smart neighbor-nudge solver.
class WidgetGridSolver {
  static bool isRectFree({
    required List<LauncherItem> items,
    required int page,
    required int x,
    required int y,
    required int spanX,
    required int spanY,
    required int columns,
    required int rows,
    Set<String> ignoreIds = const <String>{},
  }) {
    if (x < 0 ||
        y < 0 ||
        spanX < 1 ||
        spanY < 1 ||
        x + spanX > columns ||
        y + spanY > rows) {
      return false;
    }
    for (final other in items) {
      if (other.page != page || ignoreIds.contains(other.id)) continue;
      if (x < other.x + other.spanX &&
          x + spanX > other.x &&
          y < other.y + other.spanY &&
          y + spanY > other.y) {
        return false;
      }
    }
    return true;
  }

  /// Attempts to place/resize [target] to `(newX, newY, newSpanX, newSpanY)` on
  /// [page]. If neighbors occupy those cells and free cells exist on the same
  /// page, smoothly nudges those neighbors into adjacent slots (preferring
  /// left/right horizontal shifts first) so side-by-side layouts just work!
  static bool tryApplyWidgetRect({
    required List<LauncherItem> items,
    required LauncherItem target,
    required int page,
    required int newX,
    required int newY,
    required int newSpanX,
    required int newSpanY,
    required int columns,
    required int rows,
    bool dryRun = false,
  }) {
    if (newX < 0 ||
        newY < 0 ||
        newSpanX < 1 ||
        newSpanY < 1 ||
        newX + newSpanX > columns ||
        newY + newSpanY > rows) {
      return false;
    }

    final pageItems = items
        .where((i) => i.page == page && i.id != target.id)
        .toList();

    final colliding = pageItems.where((other) {
      return newX < other.x + other.spanX &&
          newX + newSpanX > other.x &&
          newY < other.y + other.spanY &&
          newY + newSpanY > other.y;
    }).toList();

    if (colliding.isEmpty) {
      if (!dryRun) {
        target.x = newX;
        target.y = newY;
        target.spanX = newSpanX;
        target.spanY = newSpanY;
        target.page = page;
      }
      return true;
    }

    // Build virtual occupancy grid with non-colliding items + new target rect
    final occupied = List.generate(
      rows,
      (_) => List<bool>.filled(columns, false),
    );
    for (int ry = newY; ry < newY + newSpanY; ry++) {
      for (int rx = newX; rx < newX + newSpanX; rx++) {
        occupied[ry][rx] = true;
      }
    }
    final collidingIds = {for (final c in colliding) c.id};
    for (final fixed in pageItems) {
      if (collidingIds.contains(fixed.id)) continue;
      for (int ry = fixed.y; ry < fixed.y + fixed.spanY; ry++) {
        for (int rx = fixed.x; rx < fixed.x + fixed.spanX; rx++) {
          if (ry >= 0 && ry < rows && rx >= 0 && rx < columns) {
            occupied[ry][rx] = true;
          }
        }
      }
    }

    // Place larger colliding items first
    colliding.sort(
      (a, b) => (b.spanX * b.spanY).compareTo(a.spanX * a.spanY),
    );

    final relocations = <LauncherItem, (int, int)>{};

    for (final item in colliding) {
      final candidates = <(int, int, int)>[];
      for (int cy = 0; cy <= rows - item.spanY; cy++) {
        for (int cx = 0; cx <= columns - item.spanX; cx++) {
          var fits = true;
          for (int ry = cy; ry < cy + item.spanY && fits; ry++) {
            for (int rx = cx; rx < cx + item.spanX; rx++) {
              if (occupied[ry][rx]) {
                fits = false;
                break;
              }
            }
          }
          if (fits) {
            // Bias score strongly toward keeping items on the same row (left/right)
            final dx = (cx - item.x).abs();
            final dy = (cy - item.y).abs();
            final score = dy * 10 + dx;
            candidates.add((cx, cy, score));
          }
        }
      }

      if (candidates.isEmpty) {
        return false;
      }

      candidates.sort((a, b) => a.$3.compareTo(b.$3));
      final chosen = candidates.first;
      relocations[item] = (chosen.$1, chosen.$2);
      for (int ry = chosen.$2; ry < chosen.$2 + item.spanY; ry++) {
        for (int rx = chosen.$1; rx < chosen.$1 + item.spanX; rx++) {
          occupied[ry][rx] = true;
        }
      }
    }

    if (!dryRun) {
      for (final entry in relocations.entries) {
        entry.key.x = entry.value.$1;
        entry.key.y = entry.value.$2;
      }
      target.x = newX;
      target.y = newY;
      target.spanX = newSpanX;
      target.spanY = newSpanY;
      target.page = page;
    }
    return true;
  }

  /// Finds the first available `(x, y)` on [page] for `(spanX, spanY)`, scanning
  /// left-to-right on each row so widgets naturally pair side-by-side!
  static (int, int)? findFirstFreeSlot({
    required List<LauncherItem> items,
    required int page,
    required int spanX,
    required int spanY,
    required int columns,
    required int rows,
    int? preferredX,
    int? preferredY,
  }) {
    final clampedW = spanX.clamp(1, columns);
    final clampedH = spanY.clamp(1, rows);

    if (preferredX != null && preferredY != null) {
      final px = preferredX.clamp(0, columns - clampedW);
      final py = preferredY.clamp(0, rows - clampedH);
      if (isRectFree(
        items: items,
        page: page,
        x: px,
        y: py,
        spanX: clampedW,
        spanY: clampedH,
        columns: columns,
        rows: rows,
      )) {
        return (px, py);
      }
    }

    for (int y = 0; y <= rows - clampedH; y++) {
      for (int x = 0; x <= columns - clampedW; x++) {
        if (isRectFree(
          items: items,
          page: page,
          x: x,
          y: y,
          spanX: clampedW,
          spanY: clampedH,
          columns: columns,
          rows: rows,
        )) {
          return (x, y);
        }
      }
    }
    return null;
  }
}
