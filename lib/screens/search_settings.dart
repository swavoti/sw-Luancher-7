import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:swavoti/widgets/search_widget.dart';
import 'package:swavoti/screens/browser_selection.dart';


class SearchSettingsScreen extends StatefulWidget {
  const SearchSettingsScreen({super.key});

  @override
  State<SearchSettingsScreen> createState() => _SearchSettingsScreenState();
}

class _SearchSettingsScreenState extends State<SearchSettingsScreen> {
  bool _showSearchWidget = true;
  String _colorVariant = 'surface_high';

  static const _colorOptions = <({String key, String label})>[
    (key: 'surface_high', label: 'Surface High'),
    (key: 'surface_highest', label: 'Surface Highest'),
    (key: 'primary_container', label: 'Primary'),
    (key: 'secondary_container', label: 'Secondary'),
    (key: 'tertiary_container', label: 'Tertiary'),
    (key: 'inverse_surface', label: 'Inverse'),
  ];

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    SearchWidget.syncFromPrefs(prefs);

    if (mounted) {
      setState(() {
        _showSearchWidget = SearchWidget.isVisible;
        _colorVariant = SearchWidget.colorVariant;
      });
    }
  }

  Future<void> _toggleSearchWidget(bool value) async {
    await SearchWidget.setVisible(value);
    if (mounted) {
      setState(() => _showSearchWidget = value);
    }
  }

  Future<void> _setColorVariant(String variant) async {
    await SearchWidget.setColorVariant(variant);
    if (mounted) {
      setState(() => _colorVariant = variant);
    }
  }

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    return Scaffold(
      backgroundColor: surface,
      appBar: AppBar(
        title: const Text('Search Bar Settings'),
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Preview
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              'Preview',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(16),
            ),
            child: PointerInterceptor(child: SearchWidget(onRemove: () {})),
          ),
          const SizedBox(height: 24),

          SwitchListTile(
            title: const Text('Show Search Bar'),
            subtitle: const Text('Display search widget on home screen'),
            value: _showSearchWidget,
            onChanged: _toggleSearchWidget,
          ),
          const Divider(),

          ListTile(
            title: const Text('Color Variant'),
            subtitle: const Text('Material 3 dynamic color style'),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: _colorOptions.map((opt) {
              final cs = Theme.of(context).colorScheme;
              final swatchColor = SearchWidget.resolveBackgroundColor(
                cs,
                opt.key,
              );
              final selected = _colorVariant == opt.key;
              return ChoiceChip(
                selected: selected,
                onSelected: (_) => _setColorVariant(opt.key),
                avatar: Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    color: swatchColor,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: cs.outline.withValues(alpha: 0.5),
                      width: 1,
                    ),
                  ),
                ),
                label: Text(opt.label),
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
          const Divider(),

          ListTile(
            title: const Text('Default Browser'),
            subtitle: const Text('Choose app to open search results'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const BrowserSelectionScreen(),
                ),
              );
              _loadSettings();
            },
          ),
        ],
      ),
    );
  }
}

// Simple wrapper to absorb taps in preview
class PointerInterceptor extends StatelessWidget {
  final Widget child;
  const PointerInterceptor({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return AbsorbPointer(absorbing: true, child: child);
  }
}
