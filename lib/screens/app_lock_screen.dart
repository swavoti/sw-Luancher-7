import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:installed_apps/installed_apps.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:swavoti/screens/app_lock_pin_screen.dart';
import 'package:swavoti/screens/app_lock_settings.dart';
import 'package:swavoti/services/app_database_service.dart';
import 'package:swavoti/services/app_lock_service.dart';

class AppLockScreen extends StatefulWidget {
  const AppLockScreen({super.key});

  @override
  State<AppLockScreen> createState() => _AppLockScreenState();
}

class _AppLockScreenState extends State<AppLockScreen> {
  bool? _hasPin;
  // The page is gated: every time it is opened the user must enter the PIN
  // (or use biometrics) before seeing or changing anything.
  bool _unlocked = false;
  String? _error;
  int _summaryGeneration = 0;

  @override
  void initState() {
    super.initState();
    _loadPinStatus();
  }

  Future<void> _loadPinStatus() async {
    try {
      final configured = await AppLockService.hasPin();
      if (mounted) setState(() => _hasPin = configured);
    } catch (error) {
      if (mounted) setState(() => _error = 'Could not read App Lock settings: $error');
    }
  }

  Future<void> _setUpPin() async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => const AppLockPinScreen(mode: AppLockPinMode.setup),
      ),
    );
    if (saved == true && mounted) {
      setState(() {
        _hasPin = true;
        _unlocked = true;
      });
    }
  }

  Future<void> _openSettings() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => const AppLockSettingsScreen()),
    );
  }

  Future<void> _openAppPicker() async {
    if (_hasPin != true) {
      await _setUpPin();
      if (_hasPin != true || !mounted) return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (_) => const _InstalledAppsPicker(),
    );
    if (mounted) setState(() => _summaryGeneration++);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    // Gate: PIN exists but the user has not verified yet this visit.
    if (_hasPin == true && !_unlocked) {
      return AppLockPinScreen(
        mode: AppLockPinMode.verify,
        popAfterVerify: false,
        description: 'Enter your PIN to open App Lock',
        onVerified: () async {
          if (mounted) setState(() => _unlocked = true);
        },
      );
    }

    return Scaffold(
      // Solid background (the launcher window itself is transparent).
      backgroundColor: colors.surface,
      appBar: AppBar(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        title: const Text('App Lock'),
        actions: [
          if (_hasPin == true)
            IconButton(
              tooltip: 'App Lock settings',
              onPressed: _openSettings,
              icon: const Icon(Icons.settings_outlined),
            ),
        ],
      ),
      body: _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(_error!, textAlign: TextAlign.center),
              ),
            )
          : _hasPin == null
          ? const Center(child: M3EProgressIndicator.circular())
          : _hasPin!
          ? _LockedAppsSummary(key: ValueKey(_summaryGeneration))
          : Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.lock_outline_rounded,
                      size: 56,
                      color: colors.primary,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Set up your App Lock PIN',
                      style: Theme.of(context).textTheme.titleLarge,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Create and confirm a PIN (${AppLockService.minPinLength} or more digits) before choosing which apps to protect.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: _setUpPin,
                      icon: const Icon(Icons.arrow_forward_rounded),
                      label: const Text('Create PIN'),
                    ),
                  ],
                ),
              ),
            ),
      floatingActionButton: _hasPin == true
          ? FloatingActionButton(
              onPressed: _openAppPicker,
              tooltip: 'Choose apps to lock',
              child: const Icon(Icons.add_rounded),
            )
          : null,
    );
  }
}

class _LockedAppsSummary extends StatefulWidget {
  const _LockedAppsSummary({super.key});

  @override
  State<_LockedAppsSummary> createState() => _LockedAppsSummaryState();
}

class _LockedAppsSummaryState extends State<_LockedAppsSummary> {
  List<MapEntry<String, String>>? _lockedApps; // package -> display name
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final locked = await AppLockService.lockedPackages();
      final names = <String, String>{};
      try {
        for (final app in await AppDatabaseService.getAppMetadata()) {
          names[app.packageName] = app.name;
        }
      } catch (_) {}
      final entries = [
        for (final packageName in locked)
          MapEntry(packageName, names[packageName] ?? packageName),
      ]..sort((a, b) => a.value.toLowerCase().compareTo(b.value.toLowerCase()));
      if (mounted) setState(() => _lockedApps = entries);
    } catch (error) {
      if (mounted) setState(() => _error = 'Could not load locked apps: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(child: Text(_error!, textAlign: TextAlign.center));
    }
    if (_lockedApps == null) {
      return const Center(child: M3EProgressIndicator.circular());
    }
    if (_lockedApps!.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(28),
          child: Text(
            'No apps are locked yet. Use the + button to choose apps.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Text(
            'Locked apps',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        ..._lockedApps!.map(
          (entry) => ListTile(
            leading: _AppIcon(
              packageName: entry.key,
              cachedIcon: AppDatabaseService.getCachedIcon(entry.key),
            ),
            title: Text(
              entry.value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: const Icon(Icons.lock_rounded),
          ),
        ),
      ],
    );
  }
}

class _InstalledAppsPicker extends StatefulWidget {
  const _InstalledAppsPicker();

  @override
  State<_InstalledAppsPicker> createState() => _InstalledAppsPickerState();
}

class _InstalledAppsPickerState extends State<_InstalledAppsPicker> {
  static const _batchSize = 5;
  final ScrollController _scrollController = ScrollController();
  List<AppInfo> _apps = [];
  Set<String> _locked = {};
  int _visibleCount = _batchSize;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_loadNextBatch);
    _load();
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_loadNextBatch)
      ..dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final apps = await InstalledApps.getInstalledApps(
        excludeSystemApps: true,
        excludeNonLaunchableApps: true,
        withIcon: false,
      );
      final locked = await AppLockService.lockedPackages();
      apps.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      if (!mounted) return;
      setState(() {
        _apps = apps;
        _locked = locked;
        _visibleCount = _batchSize;
        _loading = false;
      });
      _scheduleViewportFill();
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = 'Could not load installed apps: $error';
          _loading = false;
        });
      }
    }
  }

  void _loadNextBatch() {
    if (!_scrollController.hasClients ||
        _loading ||
        _visibleCount >= _apps.length) {
      return;
    }
    if (_scrollController.position.extentAfter < 240) {
      setState(() {
        _visibleCount = (_visibleCount + _batchSize)
            .clamp(0, _apps.length)
            .toInt();
      });
      _scheduleViewportFill();
    }
  }

  void _scheduleViewportFill() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !_scrollController.hasClients ||
          _visibleCount >= _apps.length ||
          _scrollController.position.maxScrollExtent > 0) {
        return;
      }
      setState(() {
        _visibleCount = (_visibleCount + _batchSize)
            .clamp(0, _apps.length)
            .toInt();
      });
      _scheduleViewportFill();
    });
  }

  Future<void> _toggle(AppInfo app) async {
    final shouldLock = !_locked.contains(app.packageName);
    setState(() {
      if (shouldLock) {
        _locked.add(app.packageName);
      } else {
        _locked.remove(app.packageName);
      }
    });
    try {
      await AppLockService.setPackageLocked(app.packageName, shouldLock);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        if (shouldLock) {
          _locked.remove(app.packageName);
        } else {
          _locked.add(app.packageName);
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save this app lock: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height * 0.82;
    return SizedBox(
      height: height,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Choose apps to lock',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: M3EProgressIndicator.circular())
                : _error != null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(20),
                          child: Text(_error!, textAlign: TextAlign.center),
                        ),
                        FilledButton.tonal(
                          onPressed: _load,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  )
                : _apps.isEmpty
                ? const Center(child: Text('No launchable user apps found.'))
                : ListView.builder(
                    controller: _scrollController,
                    itemCount: _visibleCount + (_visibleCount < _apps.length ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index >= _visibleCount) {
                        return const Padding(
                          padding: EdgeInsets.all(20),
                          child: Center(
                            child: M3EProgressIndicator.circular(),
                          ),
                        );
                      }
                      final app = _apps[index];
                      return _AppLockTile(
                        app: app,
                        locked: _locked.contains(app.packageName),
                        onTap: () => _toggle(app),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _AppLockTile extends StatelessWidget {
  final AppInfo app;
  final bool locked;
  final VoidCallback onTap;

  const _AppLockTile({
    required this.app,
    required this.locked,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final icon = AppDatabaseService.getCachedIcon(app.packageName);
    return ListTile(
      leading: _AppIcon(packageName: app.packageName, cachedIcon: icon),
      title: Text(app.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: IconButton(
        tooltip: locked ? 'Unlock ${app.name}' : 'Lock ${app.name}',
        onPressed: onTap,
        icon: Icon(locked ? Icons.lock_rounded : Icons.lock_open_rounded),
      ),
      onTap: onTap,
    );
  }
}

class _AppIcon extends StatelessWidget {
  final String packageName;
  final Uint8List? cachedIcon;

  const _AppIcon({required this.packageName, required this.cachedIcon});

  @override
  Widget build(BuildContext context) {
    if (cachedIcon != null) {
      return CircleAvatar(backgroundImage: MemoryImage(cachedIcon!));
    }
    return FutureBuilder<Uint8List?>(
      future: AppDatabaseService.loadIcon(packageName),
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (bytes == null) {
          return CircleAvatar(
            backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
            child: const Icon(Icons.android_rounded),
          );
        }
        return CircleAvatar(backgroundImage: MemoryImage(bytes));
      },
    );
  }
}
