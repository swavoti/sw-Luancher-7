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
    final borderRadius = isPill ? 24.0 : 12.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final veryCompact = constraints.maxWidth < 110;
        final mediumCompact = constraints.maxWidth < 175;
        final targetHeight = (isPill ? 44.0 : 48.0).clamp(
          36.0,
          constraints.maxHeight.isFinite
              ? constraints.maxHeight.clamp(36.0, 64.0)
              : 48.0,
        );

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            LauncherService.openUrlInBrowser(
              'https://www.google.com',
              _browserPackage,
            );
          },
          child: Center(
            child: Container(
              height: targetHeight,
              decoration: BoxDecoration(
                color: colorScheme.surface,
                borderRadius: BorderRadius.circular(borderRadius),
                border: Border.all(
                  color: colorScheme.outlineVariant,
                  width: 1,
                ),
              ),
              padding: EdgeInsets.symmetric(
                horizontal: veryCompact ? 8 : (isPill ? 14 : 12),
              ),
              child: Row(
                mainAxisAlignment: veryCompact
                    ? MainAxisAlignment.center
                    : MainAxisAlignment.start,
                children: [
                  Icon(
                    Icons.search_rounded,
                    color: colorScheme.onSurfaceVariant,
                    size: 17,
                  ),
                  if (!veryCompact) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Search',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colorScheme.onSurfaceVariant,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: LauncherService.openGoogleAiMode,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Stack(
                          clipBehavior: Clip.none,
                          alignment: Alignment.center,
                          children: [
                            Icon(
                              Icons.search_rounded,
                              color: colorScheme.primary,
                              size: 18,
                            ),
                            Positioned(
                              right: -3,
                              top: -3,
                              child: Icon(
                                Icons.auto_awesome,
                                color: colorScheme.primary,
                                size: 10,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  if (!mediumCompact) ...[
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: LauncherService.openGoogleVoiceSearch,
                      child: Icon(
                        Icons.mic_rounded,
                        color: colorScheme.onSurfaceVariant,
                        size: 16,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
