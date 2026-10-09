import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:swavoti/services/app_database_service.dart';
import 'package:swavoti/services/launcher_service.dart';
import 'package:installed_apps/installed_apps.dart';

class WidgetBottomSheet extends StatefulWidget {
  final Function(Map<String, dynamic>) onWidgetSelected;

  const WidgetBottomSheet({super.key, required this.onWidgetSelected});

  @override
  State<WidgetBottomSheet> createState() => _WidgetBottomSheetState();
}

class _AppIdentity {
  final String name;
  final Uint8List? icon;
  const _AppIdentity(this.name, this.icon);
}

class _SheetRow {
  final bool isHeader;
  final String packageName;
  final Map<String, dynamic>? widgetData;
  final bool isLast;
  const _SheetRow.header(this.packageName, {required this.isLast})
    : isHeader = true,
      widgetData = null;
  const _SheetRow.widget(
    this.packageName,
    this.widgetData, {
    required this.isLast,
  }) : isHeader = false;
}

class _WidgetBottomSheetState extends State<WidgetBottomSheet> {
  final Map<String, List<Map<String, dynamic>>> _groupedWidgets = {};
  final Map<String, _AppIdentity> _appIdentity = {};
  final Set<String> _expandedPackages = {};
  final Set<String> _requestedAppIcons = {};
  bool _loadingDone = false;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(
        () => _searchQuery = _searchController.text.trim().toLowerCase(),
      );
    });
    _loadWidgetsIncremental();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadWidgetsIncremental() async {
    final all = await LauncherService.getAllWidgets();
    if (!mounted) return;
    setState(() {
      for (final w in all) {
        final pkg = w['providerPackage'] as String? ?? 'Unknown';
        _groupedWidgets.putIfAbsent(pkg, () => []).add(w);
      }
      _loadingDone = true;
    });
    unawaited(_hydrateAppIdentities());
  }

  Future<void> _hydrateAppIdentities() async {
    try {
      final apps = await InstalledApps.getInstalledApps(
        excludeSystemApps: false,
        withIcon: false,
      );
      final appsByPackage = {for (final app in apps) app.packageName: app};
      if (!mounted) return;
      setState(() {
        for (final packageName in _groupedWidgets.keys) {
          final app = appsByPackage[packageName];
          final existing = _appIdentity[packageName];
          _appIdentity[packageName] = _AppIdentity(
            app?.name ?? existing?.name ?? packageName.split('.').last,
            existing?.icon,
          );
        }
      });
    } catch (e) {
      debugPrint('WidgetBottomSheet: failed to load app labels: $e');
    }
  }

  void _requestAppIcon(String packageName) {
    if (!_requestedAppIcons.add(packageName)) return;
    unawaited(_loadAppIcon(packageName));
  }

  Future<void> _loadAppIcon(String packageName) async {
    try {
      final icon = await AppDatabaseService.loadIcon(packageName);
      if (!mounted || icon == null) return;
      final identity = _appIdentity[packageName];
      setState(() {
        _appIdentity[packageName] = _AppIdentity(
          identity?.name ?? packageName.split('.').last,
          icon,
        );
      });
    } catch (e) {
      debugPrint('WidgetBottomSheet: failed to load app icon: $e');
    }
  }

  Map<String, List<Map<String, dynamic>>> get _filtered {
    if (_searchQuery.isEmpty) return _groupedWidgets;
    final result = <String, List<Map<String, dynamic>>>{};
    for (final entry in _groupedWidgets.entries) {
      final matchingWidgets = entry.value.where((w) {
        final label = (w['label'] as String? ?? '').toLowerCase();
        final pkg = entry.key.toLowerCase();
        final appName = (_appIdentity[entry.key]?.name ?? '').toLowerCase();
        return label.contains(_searchQuery) ||
            pkg.contains(_searchQuery) ||
            appName.contains(_searchQuery);
      }).toList();
      if (matchingWidgets.isNotEmpty) {
        result[entry.key] = matchingWidgets;
      }
    }
    return result;
  }

  List<_SheetRow> _flatten(Map<String, List<Map<String, dynamic>>> filtered) {
    final rows = <_SheetRow>[];
    final keys = filtered.keys.toList();
    for (var i = 0; i < keys.length; i++) {
      final pkg = keys[i];
      final widgetsForApp = filtered[pkg]!;
      final isLastGroup = i == keys.length - 1;
      final expanded =
          _searchQuery.isNotEmpty || _expandedPackages.contains(pkg);
      rows.add(_SheetRow.header(pkg, isLast: isLastGroup));
      if (expanded) {
        for (var w = 0; w < widgetsForApp.length; w++) {
          rows.add(
            _SheetRow.widget(
              pkg,
              widgetsForApp[w],
              isLast: isLastGroup && w == widgetsForApp.length - 1,
            ),
          );
        }
      }
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final filtered = _filtered;
    final rows = _flatten(filtered);

    final childContent = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 28),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              Text(
                'Widgets',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              if (_loadingDone) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: cs.secondaryContainer,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${_groupedWidgets.values.fold(0, (s, l) => s + l.length)}',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: cs.onSecondaryContainer,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            controller: _searchController,
            textInputAction: TextInputAction.search,
            style: TextStyle(fontSize: 16, color: cs.onSurface),
            decoration: InputDecoration(
              hintText: 'Search widgets',
              hintStyle: TextStyle(color: cs.onSurfaceVariant.withOpacity(0.7)),
              prefixIcon: Icon(
                Icons.search_rounded,
                color: cs.onSurfaceVariant,
                size: 20,
              ),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: Icon(
                        Icons.close_rounded,
                        size: 18,
                        color: cs.onSurfaceVariant,
                      ),
                      onPressed: () => _searchController.clear(),
                    )
                  : null,
              filled: true,
              fillColor: cs.surfaceContainerHighest.withOpacity(0.6),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(50),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(50),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(50),
                borderSide: BorderSide(color: cs.primary, width: 1.5),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: !_loadingDone
              ? const Center(child: M3EProgressIndicator.circular())
              : rows.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.search_off_rounded,
                        size: 48,
                        color: cs.onSurfaceVariant.withOpacity(0.4),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'No widgets found',
                        style: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  physics: const ClampingScrollPhysics(),
                  cacheExtent: 400,
                  padding: const EdgeInsets.only(bottom: 32),
                  itemCount: rows.length,
                  itemBuilder: (context, index) {
                    final row = rows[index];
                    if (row.isHeader) {
                      if (_appIdentity[row.packageName]?.icon == null) {
                        _requestAppIcon(row.packageName);
                      }
                      return _AppWidgetHeader(
                        identity: _appIdentity[row.packageName],
                        packageName: row.packageName,
                        count: filtered[row.packageName]?.length ?? 0,
                        expanded:
                            _searchQuery.isNotEmpty ||
                            _expandedPackages.contains(row.packageName),
                        onTap: _searchQuery.isNotEmpty
                            ? null
                            : () => setState(() {
                                if (!_expandedPackages.add(row.packageName)) {
                                  _expandedPackages.remove(row.packageName);
                                }
                              }),
                      );
                    }
                    return _DraggableWidgetRow(
                      widgetData: row.widgetData!,
                      onWidgetSelected: widget.onWidgetSelected,
                      showDivider:
                          row.isLast == false &&
                          index + 1 < rows.length &&
                          rows[index + 1].isHeader,
                    );
                  },
                ),
        ),
      ],
    );

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: Container(
        height: MediaQuery.of(context).size.height,
        color: cs.surfaceContainerLow,
        child: childContent,
      ),
    );
  }
}

class _AppWidgetHeader extends StatelessWidget {
  final _AppIdentity? identity;
  final String packageName;
  final int count;
  final bool expanded;
  final VoidCallback? onTap;

  const _AppWidgetHeader({
    required this.identity,
    required this.packageName,
    required this.count,
    required this.expanded,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final name =
        identity?.name ?? packageName.split('.').last.replaceAll('_', ' ');
    final icon = identity?.icon;

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              children: [
                if (icon != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.memory(
                      icon,
                      width: 40,
                      height: 40,
                      fit: BoxFit.cover,
                      cacheWidth: 64,
                      gaplessPlayback: true,
                      filterQuality: FilterQuality.low,
                    ),
                  )
                else
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: cs.primaryContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.widgets_rounded,
                      color: cs.onPrimaryContainer,
                      size: 22,
                    ),
                  ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    name,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                    ),
                  ),
                ),
                Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 14,
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  expanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  color: cs.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DraggableWidgetRow extends StatelessWidget {
  final Map<String, dynamic> widgetData;
  final Function(Map<String, dynamic>) onWidgetSelected;
  final bool showDivider;

  const _DraggableWidgetRow({
    required this.widgetData,
    required this.onWidgetSelected,
    required this.showDivider,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final label = widgetData['label'] as String? ?? 'Widget';
    final previewBytes = widgetData['preview'] as Uint8List?;

    final dragData = {
      'type': 'widget_preview',
      'providerPackage': widgetData['providerPackage'],
      'providerClass': widgetData['providerClass'],
      'label': label,
      'spanX': 4,
      'spanY': 2,
    };

    final row = _WidgetRow(
      label: label,
      previewBytes: previewBytes,
      primaryColor: cs.primary,
      onTap: () => onWidgetSelected(widgetData),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        LongPressDraggable<Map<String, dynamic>>(
          data: dragData,
          delay: const Duration(milliseconds: 150),
          rootOverlay: true,
          onDragStarted: () => Navigator.pop(context),
          feedback: Material(
            color: Colors.transparent,
            child: Opacity(
              opacity: 0.85,
              child: SizedBox(
                width: MediaQuery.of(context).size.width - 64,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: row,
                ),
              ),
            ),
          ),
          childWhenDragging: Opacity(opacity: 0.3, child: row),
          child: row,
        ),
        if (showDivider)
          Divider(
            height: 1,
            thickness: 1,
            indent: 16,
            endIndent: 16,
            color: cs.outlineVariant.withOpacity(0.4),
          ),
      ],
    );
  }
}

class _WidgetRow extends StatelessWidget {
  final String label;
  final Uint8List? previewBytes;
  final Color primaryColor;
  final VoidCallback onTap;

  const _WidgetRow({
    required this.label,
    required this.previewBytes,
    required this.primaryColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 88,
              height: 64,
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
              ),
              clipBehavior: Clip.antiAlias,
              child: previewBytes != null
                  ? Image.memory(
                      previewBytes!,
                      fit: BoxFit.contain,
                      cacheWidth: 176,
                      gaplessPlayback: true,
                      filterQuality: FilterQuality.low,
                    )
                  : Icon(
                      Icons.crop_square_rounded,
                      size: 32,
                      color: cs.onSurfaceVariant.withOpacity(0.5),
                    ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w400,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(
              Icons.add_circle_outline_rounded,
              color: primaryColor,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }
}
