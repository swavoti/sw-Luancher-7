import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:swavoti/services/launcher_service.dart';

class SearchWidget extends StatefulWidget {
  final VoidCallback onRemove;

  const SearchWidget({super.key, required this.onRemove});

  @override
  State<SearchWidget> createState() => _SearchWidgetState();
}

class _SearchWidgetState extends State<SearchWidget> {
  String _style = 'normal';
  String? _browserPackage;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _style = prefs.getString('search_bar_style') ?? 'normal';
        _browserPackage = prefs.getString('search_browser_package');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isPill = _style == 'pill';
    final borderRadius = isPill ? 24.0 : 8.0;
    final widgetHeight = isPill ? 30.0 : 36.0;

    return GestureDetector(
      onLongPress: () {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Remove Search Widget?'),
            content: const Text('You can re-enable this later in Home Settings.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  widget.onRemove();
                },
                child: const Text('Remove', style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
        );
      },
      onTap: () {
        LauncherService.openUrlInBrowser('https://www.google.com', _browserPackage);
      },
      child: Container(
        height: widgetHeight,
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(borderRadius),
          border: Border.all(
            color: colorScheme.outlineVariant,
            width: 1,
          ),
        ),
        padding: EdgeInsets.symmetric(horizontal: isPill ? 16 : 14),
        child: Row(
          children: [

            Icon(
              Icons.search_rounded,
              color: colorScheme.onSurfaceVariant,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Search',
                style: TextStyle(
                  color: colorScheme.onSurfaceVariant,
                  fontSize: 14,
                ),
              ),
            ),
            GestureDetector(
              onTap: LauncherService.openGoogleVoiceSearch,
              child: Icon(
                Icons.mic_rounded,
                color: colorScheme.onSurfaceVariant,
                size: 20,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
