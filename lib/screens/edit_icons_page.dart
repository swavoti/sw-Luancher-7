import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:installed_apps/installed_apps.dart';
import 'package:soft_edge_blur/soft_edge_blur.dart';

class EditIconsPage extends StatefulWidget {
  final String backgroundWallpaperPath;
  final Uint8List? homeScreenScreenshot;

  const EditIconsPage({super.key, required this.backgroundWallpaperPath, this.homeScreenScreenshot});

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
  bool _hasLawnicons = false;
  bool _useLawnicons = false;
  bool _frostedGlassEnabled = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    bool hasLawnicons = false;
    try {
      final info = await InstalledApps.getAppInfo('app.lawnchair.lawnicons');
      hasLawnicons = info != null;
    } catch (e) {
      hasLawnicons = false;
    }
    setState(() {
      _selectedShape = prefs.getString('icon_shape') ?? 'Circle';
      _hasLawnicons = hasLawnicons;
      _useLawnicons = prefs.getBool('use_lawnicons') ?? false;
      _frostedGlassEnabled = prefs.getBool('frosted_glass_enabled') ?? true;
    });
  }

  Future<void> _saveShape(String shape) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('icon_shape', shape);
    setState(() {
      _selectedShape = shape;
    });
  }

  Widget _buildShapePreview(String shape) {
    return Container(
      width: 64,
      height: 64,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary,
        borderRadius: _getBorderRadiusForShape(shape),
        shape: shape == 'Circle' ? BoxShape.circle : BoxShape.rectangle,
      ),
      child: const Icon(Icons.android, color: Colors.white, size: 32),
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
                    _buildShapePreview(_selectedShape),
                    _buildShapePreview(_selectedShape),
                    _buildShapePreview(_selectedShape),
                    _buildShapePreview(_selectedShape),
                  ],
                ),
                const Spacer(),
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
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
                  )
                ],
              )
            ],
                        child: Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.25),
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
                          color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.9),
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
        Text(
          'Icon Pack',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Lawnicons'),
          subtitle: const Text('Requires Lawnicons app'),
          trailing: Switch(
            value: _useLawnicons,
            onChanged: (val) async {
              if (!_hasLawnicons) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Lawnicons not found on device.')),
                );
                return;
              }
              final prefs = await SharedPreferences.getInstance();
              await prefs.setBool('use_lawnicons', val);
              setState(() {
                _useLawnicons = val;
              });
            },
          ),
        ),
        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: () => Navigator.pop(context),
          style: ElevatedButton.styleFrom(
            minimumSize: const Size(double.infinity, 50),
          ),
          child: const Text('Apply'),
        ),
      ],
    );
  }
}
