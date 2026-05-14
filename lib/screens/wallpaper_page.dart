import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:swavoti/services/launcher_service.dart';
import 'package:swavoti/screens/edit_icons_page.dart';

class WallpaperPage extends StatefulWidget {
  final Uint8List? homeScreenScreenshot;
  const WallpaperPage({super.key, this.homeScreenScreenshot});

  @override
  State<WallpaperPage> createState() => _WallpaperPageState();
}

class _WallpaperPageState extends State<WallpaperPage> {
  List<String> _wallpapers = [];
  String _currentPreview = '';
  bool _isLoading = true;
  @override
  void initState() {
    super.initState();
    _loadWallpapers();
  }

  Future<void> _loadWallpapers() async {
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      final imagePaths =
          manifest
              .listAssets()
              .where(
                (String key) =>
                    key.startsWith('assets/wallpapers/') &&
                    (key.endsWith('.jpg') ||
                        key.endsWith('.jpeg') ||
                        key.endsWith('.png') ||
                        key.endsWith('.webp')),
              )
              .toList()
            ..sort(); // consistent order

      if (mounted) {
        setState(() {
          _wallpapers = imagePaths;
          if (_wallpapers.isNotEmpty) {
            _currentPreview = _wallpapers.first;
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error loading wallpapers: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showWallpaperGrid() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.9,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) {
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Select Wallpaper',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: GridView.builder(
                    controller: scrollController,
                    padding: const EdgeInsets.all(8.0),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                          childAspectRatio: 9 / 16,
                        ),
                    itemCount: _wallpapers.length,
                    itemBuilder: (context, index) {
                      final path = _wallpapers[index];
                      return GestureDetector(
                        onTap: () {
                          Navigator.pop(context); // Close grid
                          _showActionSheet(path);
                        },
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.asset(
                            path,
                            fit: BoxFit.cover,
                            cacheWidth:
                                300, // Important: heavily reduces memory & decoding time
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showActionSheet(String assetPath) {
    setState(() {
      _currentPreview = assetPath;
    });

    showModalBottomSheet(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: Text(
                  'Set Wallpaper',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.home),
                title: const Text('Home Screen'),
                onTap: () => _setWallpaper(assetPath, 1),
              ),
              ListTile(
                leading: const Icon(Icons.lock),
                title: const Text('Lock Screen'),
                onTap: () => _setWallpaper(assetPath, 2),
              ),
              ListTile(
                leading: const Icon(Icons.phonelink_setup),
                title: const Text('Home and Lock Screens'),
                onTap: () => _setWallpaper(assetPath, 3),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _setWallpaper(String assetPath, int type) async {
    Navigator.pop(context); // Close action sheet
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Setting wallpaper...')));

    try {
      final ByteData data = await rootBundle.load(assetPath);
      final Uint8List bytes = data.buffer.asUint8List();
      final success = await LauncherService.setWallpaper(bytes, type);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              success
                  ? 'Wallpaper set successfully!'
                  : 'Failed to set wallpaper.',
            ),
            backgroundColor: success ? Colors.green : Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.wallpaper),
            SizedBox(width: 8),
            Text('Wallpapers'),
          ],
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: _isLoading
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(
                    'Loading wallpapers...',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
            )
          : _wallpapers.isEmpty
          ? const Center(
              child: Text('No wallpapers found in assets/wallpapers/'),
            )
          : Column(
              children: [
                const SizedBox(height: 32),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildPreviewScreen('Lock Screen', isLockScreen: true),
                    _buildPreviewScreen('Home Screen', isLockScreen: false),
                  ],
                ),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.all(32.0),
                  child: Column(
                    children: [
                      ElevatedButton.icon(
                        icon: const Icon(Icons.edit),
                        label: const Text('Edit App Icons'),
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 56),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => EditIconsPage(
                                backgroundWallpaperPath: _currentPreview,
                                homeScreenScreenshot: widget.homeScreenScreenshot,
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.photo_library),
                        label: const Text('Change Wallpaper'),
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 56),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        onPressed: _showWallpaperGrid,
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildPreviewScreen(String label, {required bool isLockScreen}) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: colorScheme.onSurface.withOpacity(0.8),
          ),
        ),
        const SizedBox(height: 16),
        Container(
          width: 150,
          height: 300,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: colorScheme.outline, width: 4),
            image: _currentPreview.isNotEmpty
                ? DecorationImage(
                    image: AssetImage(_currentPreview),
                    fit: BoxFit.cover,
                  )
                : null,
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (widget.homeScreenScreenshot != null)
                Image.memory(
                  widget.homeScreenScreenshot!,
                  fit: BoxFit.cover,
                ),
            ],
          ),
        ),
      ],
    );
  }
}
