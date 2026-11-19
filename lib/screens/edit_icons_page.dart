import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:installed_apps/installed_apps.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:swavoti/services/app_database_service.dart';
import 'package:swavoti/services/launcher_service.dart';
import 'package:swavoti/widgets/icon_shape_clipper.dart';

class EditIconsPage extends StatefulWidget {
  final String backgroundWallpaperPath;
  final Uint8List? homeScreenScreenshot;
  final Future<void> Function()? onSettingsApplied;

  const EditIconsPage({
    super.key,
    required this.backgroundWallpaperPath,
    this.homeScreenScreenshot,
    this.onSettingsApplied,
  });

  static List<String>? _cachedPreviewPackages;
  static List<Uint8List?>? _cachedSystemPreviewIcons;
  static Future<void>? _prefetchFuture;

  /// Prefetches the 4 preview app icons into RAM so opening Edit App Icons is instant.
  static Future<void> prefetchPreviewIcons() {
    if (_cachedPreviewPackages != null && _cachedSystemPreviewIcons != null) {
      return Future.value();
    }
    return _prefetchFuture ??= _doPrefetch();
  }

  static Future<void> _doPrefetch() async {
    try {
      final cachedApps = await AppDatabaseService.getAppMetadata();
      List<String> packages;
      if (cachedApps.isNotEmpty) {
        cachedApps.sort((a, b) => a.name.compareTo(b.name));
        packages = cachedApps
            .where((app) => app.packageName != 'co.za.launcher3.swavoti')
            .take(4)
            .map((app) => app.packageName)
            .toList();
      } else {
        final apps = await InstalledApps.getInstalledApps(
          excludeSystemApps: false,
          excludeNonLaunchableApps: true,
          withIcon: false,
        );
        apps.sort((a, b) => a.name.compareTo(b.name));
        packages = apps
            .where((app) => app.packageName != 'co.za.launcher3.swavoti')
            .take(4)
            .map((app) => app.packageName)
            .toList();
      }

      final icons = await Future.wait(
        packages.map((pkg) async {
          final cached = AppDatabaseService.getCachedIcon(pkg);
          if (cached != null) return cached;
          final fromDb = await AppDatabaseService.loadIcon(pkg);
          if (fromDb != null) return fromDb;
          final info = await InstalledApps.getAppInfo(pkg);
          return info?.icon;
        }),
      );
      _cachedPreviewPackages = packages;
      _cachedSystemPreviewIcons = icons;
    } catch (e) {
      debugPrint('EditIconsPage: prefetch failed: $e');
    } finally {
      _prefetchFuture = null;
    }
  }

  @override
  State<EditIconsPage> createState() => _EditIconsPageState();
}

class _EditIconsPageState extends State<EditIconsPage> {
  static const _shapes = [
    'Circle',
    'Squircle',
    'Rounded Rectangle',
    'Teardrop',
  ];

  String _selectedShape = 'Circle';
  String _selectedIconPack = '';
  bool _themedIconsEnabled = false;
  List<Map<String, dynamic>> _availableIconPacks = [];
  List<String> _previewPackages = [];
  List<Uint8List?> _systemPreviewIcons = [];
  List<Uint8List?> _previewIcons = [];
  final Map<String, Uint8List?> _monochromeIcons = {};
  bool _isLoadingPreview = true;
  bool _isApplying = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadPreviewIcons();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final packs = await LauncherService.getAvailableIconPacks();
    if (!mounted) return;
    setState(() {
      _selectedShape = prefs.getString('icon_shape') ?? 'Circle';
      _selectedIconPack = prefs.getString('icon_pack') ?? '';
      _themedIconsEnabled = prefs.getBool('themed_icons_enabled') ?? false;
      _availableIconPacks = packs;
    });
    if (_previewPackages.isNotEmpty) {
      await _loadPreviewForPack(_selectedIconPack);
      if (_themedIconsEnabled) {
        await _loadMonochromeIcons();
      }
    }
  }

  Future<void> _loadMonochromeIcons() async {
    for (final pkg in _previewPackages) {
      if (!_monochromeIcons.containsKey(pkg)) {
        final mono = await LauncherService.getMonochromeIcon(pkg);
        if (mounted) {
          setState(() {
            _monochromeIcons[pkg] = mono;
          });
        }
      }
    }
  }

  Future<void> _loadPreviewIcons() async {
    try {
      if (EditIconsPage._cachedPreviewPackages != null &&
          EditIconsPage._cachedSystemPreviewIcons != null) {
        if (mounted) {
          setState(() {
            _previewPackages = List.of(EditIconsPage._cachedPreviewPackages!);
            _systemPreviewIcons =
                List.of(EditIconsPage._cachedSystemPreviewIcons!);
            _previewIcons = List.of(EditIconsPage._cachedSystemPreviewIcons!);
            _isLoadingPreview = false;
          });
        }
        if (_selectedIconPack.isNotEmpty) {
          await _loadPreviewForPack(_selectedIconPack);
        }
        _loadMonochromeIcons();
        return;
      }

      await EditIconsPage.prefetchPreviewIcons();
      if (!mounted) return;
      final packages = EditIconsPage._cachedPreviewPackages ?? [];
      final icons = EditIconsPage._cachedSystemPreviewIcons ?? [];
      setState(() {
        _previewPackages = List.of(packages);
        _systemPreviewIcons = List.of(icons);
        _previewIcons = List.of(icons);
        _isLoadingPreview = false;
      });
      if (_selectedIconPack.isNotEmpty) {
        await _loadPreviewForPack(_selectedIconPack);
      }
      _loadMonochromeIcons();
    } catch (e) {
      debugPrint('EditIconsPage: failed to load preview icons: $e');
      if (mounted) setState(() => _isLoadingPreview = false);
    }
  }

  Future<void> _loadPreviewForPack(String packageName) async {
    if (packageName.isEmpty) {
      if (mounted) setState(() => _previewIcons = _systemPreviewIcons);
      return;
    }
    if (_previewPackages.isEmpty) return;
    try {
      final themedIcons = await Future.wait(
        _previewPackages.map(
          (appPackage) => LauncherService.getThemedIcon(
            appPackage,
            packageName,
          ),
        ),
      );
      if (!mounted || packageName != _selectedIconPack) return;
      setState(() {
        _previewIcons = List.generate(
          _previewPackages.length,
          (index) => themedIcons[index] ?? _systemPreviewIcons[index],
        );
      });
    } catch (e) {
      debugPrint('EditIconsPage: failed to preview icon pack: $e');
    }
  }

  Future<void> _saveShape(String shape) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('icon_shape', shape);
    if (mounted) setState(() => _selectedShape = shape);
  }

  Future<void> _selectIconShape() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: cs.outlineVariant,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Text(
                    'Icon shape',
                    style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                for (final shape in _shapes)
                  ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    leading: IconShapeClipper(
                      shape: shape,
                      size: 36,
                      child: Container(
                        width: 36,
                        height: 36,
                        color: shape == _selectedShape
                            ? cs.primary
                            : cs.primaryContainer,
                        alignment: Alignment.center,
                        child: Icon(
                          Icons.apps_rounded,
                          size: 18,
                          color: shape == _selectedShape
                              ? cs.onPrimary
                              : cs.onPrimaryContainer,
                        ),
                      ),
                    ),
                    title: Text(
                      shape,
                      style: TextStyle(
                        fontWeight: shape == _selectedShape
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                    trailing: shape == _selectedShape
                        ? Icon(Icons.check_rounded, color: cs.primary)
                        : null,
                    onTap: () => Navigator.pop(ctx, shape),
                  ),
              ],
            ),
          ),
        );
      },
    );
    if (selected != null && mounted) {
      await _saveShape(selected);
    }
  }

  Future<void> _selectIconPack() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (context) => _IconPackPicker(
        packs: _availableIconPacks,
        selectedPackage: _selectedIconPack,
      ),
    );
    if (selected == null || !mounted) return;
    setState(() {
      _selectedIconPack = selected;
      _isLoadingPreview = _previewIcons.isEmpty;
    });
    await _loadPreviewForPack(selected);
  }

  Future<void> _apply() async {
    setState(() => _isApplying = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('icon_shape', _selectedShape);
      await prefs.setString('icon_pack', _selectedIconPack);
      await prefs.setBool('themed_icons_enabled', _themedIconsEnabled);
      AppDatabaseService.currentIconPack = _selectedIconPack;
      await AppDatabaseService.clearIconCache();
      await widget.onSettingsApplied?.call();
      if (mounted) {
        if (Navigator.canPop(context)) {
          Navigator.pop(context, true);
        } else {
          SystemNavigator.pop();
        }
      }
    } catch (e) {
      debugPrint('EditIconsPage: failed to apply icon settings: $e');
      if (mounted) {
        setState(() => _isApplying = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not apply icon settings.')),
        );
      }
    }
  }


  Widget _buildPreviewIcon(int index) {
    final icon = index < _previewIcons.length ? _previewIcons[index] : null;
    final pkg = index < _previewPackages.length ? _previewPackages[index] : null;
    final monoBytes = pkg != null ? _monochromeIcons[pkg] : null;
    final colors = Theme.of(context).colorScheme;

    Widget rawIcon = icon == null
        ? const Icon(Icons.android, size: 40)
        : Image.memory(
            icon,
            width: 56,
            height: 56,
            fit: BoxFit.cover,
            cacheWidth: 112,
            gaplessPlayback: true,
          );

    if (_themedIconsEnabled && monoBytes != null) {
      return IconShapeClipper(
        shape: _selectedShape,
        size: 56,
        child: Container(
          width: 56,
          height: 56,
          color: colors.surfaceContainerHighest,
          alignment: Alignment.center,
          child: ColorFiltered(
            colorFilter: ColorFilter.mode(
              colors.primary,
              BlendMode.srcIn,
            ),
            child: SizedBox(
              width: 32,
              height: 32,
              child: Image.memory(
                monoBytes,
                width: 32,
                height: 32,
                fit: BoxFit.contain,
                cacheWidth: 64,
                gaplessPlayback: true,
              ),
            ),
          ),
        ),
      );
    }

    return IconShapeClipper(
      shape: _selectedShape,
      size: 56,
      child: rawIcon,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final selectedPack = _availableIconPacks.cast<Map<String, dynamic>?>().firstWhere(
      (pack) => pack?['packageName'] == _selectedIconPack,
      orElse: () => null,
    );
    final packIcon = selectedPack?['icon'] as Uint8List?;
    final packLabel = selectedPack?['label'] as String? ?? 'System Default';

    return Scaffold(
      backgroundColor: colors.surface,
      appBar: AppBar(
        title: const Text('Edit App Icons'),
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
      ),
      body: Stack(
        children: [
          if (widget.homeScreenScreenshot != null)
            Positioned.fill(
              child: Image.memory(
                widget.homeScreenScreenshot!,
                fit: BoxFit.cover,
              ),
            )
          else if (widget.backgroundWallpaperPath.isNotEmpty)
            Positioned.fill(
              child: Image.asset(
                widget.backgroundWallpaperPath,
                fit: BoxFit.cover,
              ),
            ),
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
              children: [
                Text(
                  'Preview',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 20),
                Center(
                  child: _isLoadingPreview
                      ? const SizedBox(
                          height: 64,
                          width: 64,
                          child: CircularProgressIndicator(),
                        )
                      : Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 20,
                          runSpacing: 20,
                          children: List.generate(
                            max(4, _previewPackages.length),
                            _buildPreviewIcon,
                          ),
                        ),
                ),
                const SizedBox(height: 36),
                Text(
                  'Icon shape',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: IconShapeClipper(
                    shape: _selectedShape,
                    size: 40,
                    child: Container(
                      width: 40,
                      height: 40,
                      color: colors.primaryContainer,
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.apps_rounded,
                        size: 20,
                        color: colors.onPrimaryContainer,
                      ),
                    ),
                  ),
                  title: Text(_selectedShape),
                  subtitle: const Text('Tap to choose icon shape'),
                  trailing: const Icon(Icons.arrow_drop_down),
                  onTap: _selectIconShape,
                ),
                const SizedBox(height: 16),
                Text(
                  'Icon pack',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: packIcon == null
                      ? Icon(Icons.apps_outlined, color: colors.primary)
                      : Image.memory(
                          packIcon,
                          width: 40,
                          height: 40,
                          cacheWidth: 80,
                          fit: BoxFit.cover,
                        ),
                  title: Text(packLabel),
                  subtitle: Text(
                    _selectedIconPack.isEmpty
                        ? 'Choose an installed icon pack'
                        : _selectedIconPack,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: const Icon(Icons.arrow_drop_down),
                  onTap: _selectIconPack,
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: Icon(
                    Icons.palette_outlined,
                    color: colors.primary,
                  ),
                  title: const Text(
                    'Themed icons',
                    style: TextStyle(fontWeight: FontWeight.w500),
                  ),
                  subtitle: Text(
                    'Tint icons with wallpaper and dynamic theme',
                    style: TextStyle(
                      color: colors.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                  value: _themedIconsEnabled,
                  onChanged: (val) async {
                    setState(() => _themedIconsEnabled = val);
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setBool('themed_icons_enabled', val);
                    if (val) {
                      await _loadMonochromeIcons();
                    }
                  },
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _isApplying ? null : _apply,
                  child: _isApplying
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Apply'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _IconPackPicker extends StatefulWidget {
  final List<Map<String, dynamic>> packs;
  final String selectedPackage;

  const _IconPackPicker({
    required this.packs,
    required this.selectedPackage,
  });

  @override
  State<_IconPackPicker> createState() => _IconPackPickerState();
}

class _IconPackPickerState extends State<_IconPackPicker> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _query.toLowerCase();
    final packs = widget.packs.where((pack) {
      final label = (pack['label'] as String? ?? '').toLowerCase();
      final packageName = (pack['packageName'] as String? ?? '').toLowerCase();
      return label.contains(query) || packageName.contains(query);
    }).toList();

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.78,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Choose icon pack',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 12),
                TextField(
                  controller: _searchController,
                  onChanged: (value) => setState(() => _query = value.trim()),
                  decoration: const InputDecoration(
                    hintText: 'Search icon packs',
                    prefixIcon: Icon(Icons.search),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              children: [
                ListTile(
                  leading: const Icon(Icons.apps_outlined),
                  title: const Text('System Default'),
                  trailing: widget.selectedPackage.isEmpty
                      ? const Icon(Icons.check)
                      : null,
                  onTap: () => Navigator.pop(context, ''),
                ),
                for (final pack in packs)
                  ListTile(
                    leading: pack['icon'] is Uint8List
                        ? Image.memory(
                            pack['icon'] as Uint8List,
                            width: 40,
                            height: 40,
                            fit: BoxFit.cover,
                            cacheWidth: 80,
                          )
                        : const Icon(Icons.apps_outlined),
                    title: Text(pack['label'] as String? ?? 'Icon pack'),
                    subtitle: Text(
                      pack['packageName'] as String? ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing:
                        pack['packageName'] == widget.selectedPackage
                            ? const Icon(Icons.check)
                            : null,
                    onTap: () => Navigator.pop(
                      context,
                      pack['packageName'] as String? ?? '',
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
