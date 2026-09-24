import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:swavoti/services/launcher_service.dart';
import 'package:installed_apps/installed_apps.dart';
import 'package:installed_apps/app_info.dart';

class WidgetBottomSheet extends StatefulWidget {
  final Function(Map<String, dynamic>) onWidgetSelected;

  const WidgetBottomSheet({super.key, required this.onWidgetSelected});

  @override
  State<WidgetBottomSheet> createState() => _WidgetBottomSheetState();
}

class _WidgetBottomSheetState extends State<WidgetBottomSheet> {
  final Map<String, List<Map<String, dynamic>>> _groupedWidgets = {};
  bool _loadingDone = false;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _frostedGlassEnabled = false;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text.trim().toLowerCase());
    });
    _loadSettings();
    _loadWidgetsIncremental();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _frostedGlassEnabled = prefs.getBool('frosted_glass_enabled') ?? false;
      });
    }
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
  }

  /// Returns filtered groups based on current search query.
  Map<String, List<Map<String, dynamic>>> get _filtered {
    if (_searchQuery.isEmpty) return _groupedWidgets;
    final result = <String, List<Map<String, dynamic>>>{};
    for (final entry in _groupedWidgets.entries) {
      final matchingWidgets = entry.value.where((w) {
        final label = (w['label'] as String? ?? '').toLowerCase();
        final pkg = entry.key.toLowerCase();
        return label.contains(_searchQuery) || pkg.contains(_searchQuery);
      }).toList();
      if (matchingWidgets.isNotEmpty) {
        result[entry.key] = matchingWidgets;
      }
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final filtered = _filtered;

    final childContent = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 28),
        // ── Title + count ────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              Text(
                'Widgets',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
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
                      fontSize: 12,
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

        // ── Search pill ──────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            controller: _searchController,
            textInputAction: TextInputAction.search,
            style: TextStyle(fontSize: 15, color: cs.onSurface),
            decoration: InputDecoration(
              hintText: 'Search widgets',
              hintStyle: TextStyle(
                color: cs.onSurfaceVariant.withOpacity(0.7),
              ),
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

        // ── List ────────────────────────────────────────────────
        Expanded(
          child: !_loadingDone
              ? const Center(child: CircularProgressIndicator())
              : filtered.isEmpty
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
                  padding: const EdgeInsets.only(bottom: 32),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final pkg = filtered.keys.elementAt(index);
                    final widgetsForApp = filtered[pkg]!;

                    return _AppWidgetGroup(
                      packageName: pkg,
                      widgets: widgetsForApp,
                      onWidgetSelected: widget.onWidgetSelected,
                      isLast: index == filtered.length - 1,
                    );
                  },
                ),
        ),
      ],
    );

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: _frostedGlassEnabled
        ? BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              height: MediaQuery.of(context).size.height,
              decoration: BoxDecoration(
                color: cs.surface.withValues(alpha: 0.65),
              ),
              child: childContent,
            ),
          )
        : Container(
            height: MediaQuery.of(context).size.height,
            color: cs.surface,
            child: childContent,
          ),
    );
  }
}

// ─── App group: inline, no card ─────────────────────────────────────────────

class _AppWidgetGroup extends StatelessWidget {
  final String packageName;
  final List<Map<String, dynamic>> widgets;
  final Function(Map<String, dynamic>) onWidgetSelected;
  final bool isLast;

  const _AppWidgetGroup({
    required this.packageName,
    required this.widgets,
    required this.onWidgetSelected,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // App header row
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Row(
            children: [
              // App icon
              FutureBuilder<AppInfo?>(
                future: InstalledApps.getAppInfo(packageName),
                builder: (context, snapshot) {
                  if (snapshot.hasData && snapshot.data?.icon != null) {
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.memory(
                        snapshot.data!.icon!,
                        width: 32,
                        height: 32,
                        fit: BoxFit.cover,
                      ),
                    );
                  }
                  return Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: cs.primaryContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.widgets_rounded,
                      color: cs.onPrimaryContainer,
                      size: 18,
                    ),
                  );
                },
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FutureBuilder<AppInfo?>(
                  future: InstalledApps.getAppInfo(packageName),
                  builder: (context, snapshot) {
                    final name =
                        snapshot.data?.name ??
                        packageName.split('.').last.replaceAll('_', ' ');
                    return Text(
                      name,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface,
                      ),
                    );
                  },
                ),
              ),
              // Widget count badge
              Text(
                '${widgets.length}',
                style: TextStyle(
                  fontSize: 12,
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),

        // Widget rows — flat, no card
        ...widgets.map((widgetData) {
          final label = widgetData['label'] as String? ?? 'Widget';
          final previewBytes = widgetData['preview'] as Uint8List?;

          final dragData = {
            'type': 'widget_preview',
            'providerPackage': widgetData['providerPackage'],
            'providerClass': widgetData['providerClass'],
            'label': label,
          };

          final row = _WidgetRow(
            label: label,
            previewBytes: previewBytes,
            primaryColor: cs.primary,
            onTap: () => onWidgetSelected(widgetData),
          );

          return LongPressDraggable<Map<String, dynamic>>(
            data: dragData,
            delay: const Duration(milliseconds: 150),
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
          );
        }),

        // Divider between groups
        if (!isLast)
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

// ─── Single widget row ───────────────────────────────────────────────────────

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
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Row(
          children: [
            // Preview thumbnail
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
              ),
              clipBehavior: Clip.antiAlias,
              child: previewBytes != null
                  ? Image.memory(
                      previewBytes!,
                      fit: BoxFit.cover,
                    )
                  : Icon(
                      Icons.crop_square_rounded,
                      size: 24,
                      color: cs.onSurfaceVariant.withOpacity(0.5),
                    ),
            ),
            const SizedBox(width: 14),
            // Label
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // Add button
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
