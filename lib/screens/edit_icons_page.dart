import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
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
    }
  }

  Future<void> _loadPreviewIcons() async {
    try {
      final apps = await InstalledApps.getInstalledApps(
        excludeSystemApps: false,
        excludeNonLaunchableApps: true,
        withIcon: false,
      );
      apps.sort((a, b) => a.name.compareTo(b.name));
      final packages = apps
          .where((app) => app.packageName != 'co.za.launcher3.swavoti')
          .take(4)
          .map((app) => app.packageName)
          .toList();
      final icons = await Future.wait(
        packages.map((packageName) async {
          final info = await InstalledApps.getAppInfo(packageName);
          return info?.icon;
        }),
      );
      if (!mounted) return;
      setState(() {
        _previewPackages = packages;
        _systemPreviewIcons = icons;
        _previewIcons = icons;
        _isLoadingPreview = false;
      });
      if (_selectedIconPack.isNotEmpty) {
        await _loadPreviewForPack(_selectedIconPack);
      }
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
      if (mounted) Navigator.pop(context, true);
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

  void _showThemedIconsSheet() {
    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheetState) {
          final colors = Theme.of(context).colorScheme;
          return Container(
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            ),
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: colors.onSurfaceVariant.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: colors.primaryContainer,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        Icons.auto_awesome_rounded,
                        color: colors.primary,
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                'Themed Icons',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: colors.secondaryContainer,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  'BETA',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: colors.onSecondaryContainer,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Material You dynamic color theming',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerHighest.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: colors.outlineVariant.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Text(
                    'Supported app icons adopt colors from your wallpaper and Android dynamic theme. The launcher applies adaptive monochrome tints calculated by your device.',
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Enable themed icons',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    _themedIconsEnabled ? 'Enabled' : 'Disabled',
                    style: TextStyle(
                      color: _themedIconsEnabled
                          ? colors.primary
                          : colors.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                  value: _themedIconsEnabled,
                  onChanged: (val) async {
                    setSheetState(() => _themedIconsEnabled = val);
                    setState(() => _themedIconsEnabled = val);
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setBool('themed_icons_enabled', val);
                  },
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Done'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildPreviewIcon(int index) {
    final icon = index < _previewIcons.length ? _previewIcons[index] : null;
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

    if (_themedIconsEnabled) {
      return IconShapeClipper(
        shape: _selectedShape,
        size: 56,
        child: Container(
          width: 56,
          height: 56,
          color: colors.primaryContainer,
          alignment: Alignment.center,
          child: ColorFiltered(
            colorFilter: ColorFilter.mode(
              colors.primary,
              BlendMode.srcIn,
            ),
            child: SizedBox(
              width: 32,
              height: 32,
              child: rawIcon,
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
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: ActionChip(
              avatar: Icon(
                Icons.auto_awesome,
                size: 15,
                color: _themedIconsEnabled ? colors.primary : colors.onSurfaceVariant,
              ),
              label: Text(
                'Themed icons (Beta)',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: _themedIconsEnabled ? colors.primary : colors.onSurfaceVariant,
                ),
              ),
              backgroundColor: _themedIconsEnabled
                  ? colors.primaryContainer.withValues(alpha: 0.7)
                  : colors.surfaceContainerHighest.withValues(alpha: 0.5),
              side: BorderSide(
                color: _themedIconsEnabled
                    ? colors.primary.withValues(alpha: 0.4)
                    : colors.outlineVariant.withValues(alpha: 0.3),
              ),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              onPressed: _showThemedIconsSheet,
            ),
          ),
        ],
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
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Preview',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: _showThemedIconsSheet,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: _themedIconsEnabled
                              ? colors.primaryContainer
                              : colors.surfaceContainerHighest.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: _themedIconsEnabled
                                ? colors.primary.withValues(alpha: 0.5)
                                : colors.outlineVariant.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.auto_awesome_rounded,
                              size: 13,
                              color: _themedIconsEnabled
                                  ? colors.primary
                                  : colors.onSurfaceVariant,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Themed icons (Beta)',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: _themedIconsEnabled
                                    ? colors.onPrimaryContainer
                                    : colors.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
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
                const SizedBox(height: 8),
                DropdownButton<String>(
                  value: _selectedShape,
                  isExpanded: true,
                  underline: const Divider(height: 1),
                  items: _shapes
                      .map(
                        (shape) => DropdownMenuItem(
                          value: shape,
                          child: Text(shape),
                        ),
                      )
                      .toList(),
                  onChanged: (shape) {
                    if (shape != null) _saveShape(shape);
                  },
                ),
                const SizedBox(height: 24),
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
