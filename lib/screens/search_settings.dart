import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:swavoti/widgets/search_widget.dart';
import 'package:swavoti/screens/browser_selection.dart';
import 'package:swavoti/services/launcher_service.dart';

class SearchSettingsScreen extends StatefulWidget {
  const SearchSettingsScreen({super.key});

  @override
  State<SearchSettingsScreen> createState() => _SearchSettingsScreenState();
}

class _SearchSettingsScreenState extends State<SearchSettingsScreen> {
  bool _showSearchWidget = true;
  String _searchBarStyle = 'normal';
  String? _browserPackage;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final savedItems = prefs.getStringList('launcher_items') ?? [];
    
    bool hasSearchWidget = false;
    for (final jsonStr in savedItems) {
      if (jsonStr.contains('"type":"search_widget"')) {
        hasSearchWidget = true;
        break;
      }
    }

    if (mounted) {
      setState(() {
        _showSearchWidget = hasSearchWidget;
        _searchBarStyle = prefs.getString('search_bar_style') ?? 'normal';
        _browserPackage = prefs.getString('search_browser_package');
      });
    }
  }

  Future<void> _toggleSearchWidget(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    final savedItems = prefs.getStringList('launcher_items') ?? [];
    
    if (value) {
      if (!savedItems.any((jsonStr) => jsonStr.contains('"type":"search_widget"'))) {
        savedItems.add('{"id":"search_default","type":"search_widget","packageName":"","className":null,"appWidgetId":null,"x":0,"y":0,"spanX":4,"spanY":1,"page":0,"label":"Search"}');
        await prefs.setStringList('launcher_items', savedItems);
      }
    } else {
      savedItems.removeWhere((jsonStr) => jsonStr.contains('"type":"search_widget"'));
      await prefs.setStringList('launcher_items', savedItems);
    }
    
    setState(() => _showSearchWidget = value);
  }

  Future<void> _setStyle(String style) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('search_bar_style', style);
    setState(() => _searchBarStyle = style);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Search Bar Settings'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Preview
          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              'Preview',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(16),
            ),
            child: PointerInterceptor(
              child: SearchWidget(onRemove: () {}),
            ),
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
            title: const Text('Bar Style'),
            subtitle: Text(_searchBarStyle.toUpperCase()),
          ),
          Row(
            children: [
              Expanded(
                child: RadioListTile<String>(
                  title: const Text('Normal'),
                  value: 'normal',
                  groupValue: _searchBarStyle,
                  onChanged: (val) {
                    if (val != null) _setStyle(val);
                  },
                ),
              ),
              Expanded(
                child: RadioListTile<String>(
                  title: const Text('Pill'),
                  value: 'pill',
                  groupValue: _searchBarStyle,
                  onChanged: (val) {
                    if (val != null) _setStyle(val);
                  },
                ),
              ),
            ],
          ),
          const Divider(),
          
          ListTile(
            title: const Text('Default Browser'),
            subtitle: const Text('Choose app to open search results'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const BrowserSelectionScreen()),
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
    return AbsorbPointer(
      absorbing: true,
      child: child,
    );
  }
}
