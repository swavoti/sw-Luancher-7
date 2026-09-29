cat << 'INNER_EOF' > lib/screens/edit_icons_page.dart
import 'dart:typed_data';
import 'dart:ui';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:installed_apps/installed_apps.dart';
import 'package:installed_apps/app_info.dart';
import 'package:soft_edge_blur/soft_edge_blur.dart';
import 'package:swavoti/services/launcher_service.dart';
import 'package:swavoti/services/app_database_service.dart';

class EditIconsPage extends StatefulWidget {
  final String backgroundWallpaperPath;
  final Uint8List? homeScreenScreenshot;

  const EditIconsPage({
    super.key,
    required this.backgroundWallpaperPath,
    this.homeScreenScreenshot,
  });

  @override
  State<EditIconsPage> createState() => _EditIconsPageState();
}

class _EditIconsPageState extends State<EditIconsPage> {
  String _selectedShape = 'Circle';
  final List<String> _shapes = [
    'Circle',
    'Squircle',
    'Rounded Rectangle',
    'Teardrop',
  ];
  bool _frostedGlassEnabled = true;
  
  List<Map<String, dynamic>> _availableIconPacks = [];
  String _selectedIconPack = "";
  
  List<Uint8List> _previewIcons = [];
  bool _isLoadingPreview = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadPreviewIcons();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    
    final packs = await LauncherService.getAvailableIconPacks();
    
    setState(() {
      _selectedShape = prefs.getString('icon_shape') ?? 'Circle';
      _selectedIconPack = prefs.getString('icon_pack') ?? "";
      _availableIconPacks = packs;
      _frostedGlassEnabled = prefs.getBool('frosted_glass_enabled') ?? true;
    });
  }
  
  Future<void> _loadPreviewIcons() async {
    try {
      final apps = await InstalledApps.getInstalledApps(excludeSystemApps: false, withIcon: true);
      if (apps.isNotEmpty) {
        apps.shuffle(Random());
        final selected = apps.take(4).toList();
        final icons = <Uint8List>[];
        for (var app in selected) {
          if (app.icon != null) {
            icons.add(app.icon!);
          }
        }
        if (mounted) {
          setState(() {
            _previewIcons = icons;
            _isLoadingPreview = false;
          });
        }
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingPreview = false);
    }
  }

  Future<void> _saveShape(String shape) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('icon_shape', shape);
    setState(() {
      _selectedShape = shape;
    });
  }

  Widget _buildShapePreview(String shape, int index) {
    Widget content;
    if (_isLoadingPreview || _previewIcons.isEmpty || index >= _previewIcons.length) {
      // Skeleton loader
      content = Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.3),
          shape: BoxShape.circle,
        ),
      );
    } else {
      content = Image.memory(
        _previewIcons[index],
        width: 48,
        height: 48,
        fit: BoxFit.cover,
      );
    }
  
    return Container(
      width: 64,
      height: 64,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withOpacity(0.2),
        borderRadius: _getBorderRadiusForShape(shape),
        shape: shape == 'Circle' ? BoxShape.circle : BoxShape.rectangle,
      ),
      child: Center(
        child: ClipRRect(
          borderRadius: _getBorderRadiusForShape(shape) ?? BorderRadius.circular(32),
          child: content,
        ),
      ),
    );
  }

  BorderRadiusGeometry? _getBorderRadiusForShape(String shape) {
    if (shape == 'Circle') return null;
    if (shape == 'Rounded Rectangle') return BorderRadius.circular(16);
    if (shape == 'Squircle') return BorderRadius.circular(24);
    if (shape == 'Teardrop') {
      return const BorderRadius.only(
        topLeft: Radius.circular(32),
        topRight: Radius.circular(32),
        bottomLeft: Radius.circular(32),
        bottomRight: Radius.circular(4),
      );
    }
    return BorderRadius.circular(12);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Edit App Icons'),
        backgroundColor: Colors.transparent,
        elevation: 0,
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
            )
          else
            Container(color: Theme.of(context).colorScheme.surface),

          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 60),
                // Preview Area
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildShapePreview(_selectedShape, 0),
                    _buildShapePreview(_selectedShape, 1),
                    _buildShapePreview(_selectedShape, 2),
                    _buildShapePreview(_selectedShape, 3),
                  ],
                ),
                const Spacer(),
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(32),
                  ),
                  child: _frostedGlassEnabled
                      ? SoftEdgeBlur(
                          edges: [
                            EdgeBlur(
                              type: EdgeType.topEdge,
                              size: 100,
                              sigma: 30,
                              controlPoints: [
                                ControlPoint(
                                  position: 0.5,
                                  type: ControlPointType.visible,
                                ),
                                ControlPoint(
                                  position: 1,
                                  type: ControlPointType.transparent,
                                ),
                              ],
                            ),
                          ],
                          child: Container(
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: Theme.of(
                                context,
                              ).colorScheme.surface.withValues(alpha: 0.25),
                              border: Border(
                                top: BorderSide(
                                  color: Colors.white.withValues(alpha: 0.15),
                                  width: 1,
                                ),
                              ),
                            ),
                            child: _buildPanelContent(),
                          ),
                        )
                      : Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: Theme.of(
                              context,
                            ).colorScheme.surface.withValues(alpha: 0.9),
                          ),
                          child: _buildPanelContent(),
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPanelContent() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Select Icon Shape',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: _shapes.map((shape) {
            final isSelected = _selectedShape == shape;
            return ChoiceChip(
              label: Text(shape),
              selected: isSelected,
              onSelected: (selected) {
                if (selected) _saveShape(shape);
              },
            );
          }).toList(),
        ),
        const SizedBox(height: 24),
        Text('Icon Pack', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _selectedIconPack,
              isExpanded: true,
              items: [
                const DropdownMenuItem(
                  value: "",
                  child: Text("System Default"),
                ),
                ..._availableIconPacks.map((pack) {
                  return DropdownMenuItem(
                    value: pack['packageName'] as String,
                    child: Text(pack['label'] as String),
                  );
                }),
              ],
              onChanged: (val) async {
                if (val != null) {
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setString('icon_pack', val);
                  setState(() => _selectedIconPack = val);
                }
              },
            ),
          ),
        ),
        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: () async {
            // Apply icon pack
            AppDatabaseService.currentIconPack = _selectedIconPack;
            await AppDatabaseService.clearIconCache();
            if (mounted) Navigator.pop(context, true);
          },
          style: ElevatedButton.styleFrom(
            minimumSize: const Size(double.infinity, 50),
          ),
          child: const Text('Apply'),
        ),
      ],
    );
  }
}
INNER_EOF
