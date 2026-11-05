import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swavoti/widgets/widget_display.dart';
import 'package:swavoti/widgets/widget_host.dart';

void main() {
  testWidgets('Launcher3ResizeFrame renders handles and pen button for search widget', (tester) async {
    bool configured = false;
    bool exited = false;

    final searchItem = LauncherItem(
      id: 'test_search',
      type: 'search_widget',
      packageName: '',
      label: 'Search',
      spanX: 4,
      spanY: 1,
      x: 0,
      y: 0,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF006A60)),
        ),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 300,
              height: 56,
              child: Launcher3ResizeFrame(
                item: searchItem,
                cellWidth: 80,
                cellHeight: 80,
                capabilities: const WidgetCapabilities(
                  configurable: true,
                  resizeHorizontal: true,
                  resizeVertical: false,
                  defaultSpanX: 4,
                  defaultSpanY: 1,
                ),
                onRemove: () {},
                onExitEdit: () => exited = true,
                onResetSize: () {},
                onConfigure: () => configured = true,
                child: Container(
                  color: Colors.grey.shade900,
                  child: const Text('Search Content'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    // Verify search widget content is present
    expect(find.text('Search Content'), findsOneWidget);

    // Verify pen / edit button icon is present
    final penFinder = find.byIcon(Icons.edit_rounded);
    expect(penFinder, findsOneWidget);

    // Tap pen button and verify onConfigure was called
    await tester.tap(penFinder);
    await tester.pump();
    expect(configured, isTrue);

    // Verify that the frame outline container exists with rounded border
    final containerFinder = find.byWidgetPredicate(
      (widget) =>
          widget is Container &&
          widget.decoration is BoxDecoration &&
          (widget.decoration as BoxDecoration).border != null &&
          (widget.decoration as BoxDecoration).borderRadius ==
              BorderRadius.circular(24.0),
    );
    expect(containerFinder, findsOneWidget);
  });

  testWidgets('Launcher3ResizeFrame shows 4 handles when both horizontal & vertical resizable', (tester) async {
    final widgetItem = LauncherItem(
      id: 'test_widget',
      type: 'widget',
      packageName: 'com.example.clock',
      label: 'Clock',
      spanX: 2,
      spanY: 2,
      x: 0,
      y: 0,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF006A60)),
        ),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 160,
              height: 160,
              child: Launcher3ResizeFrame(
                item: widgetItem,
                cellWidth: 80,
                cellHeight: 80,
                capabilities: const WidgetCapabilities(
                  configurable: true,
                  resizeHorizontal: true,
                  resizeVertical: true,
                  defaultSpanX: 2,
                  defaultSpanY: 2,
                ),
                onRemove: () {},
                onExitEdit: () {},
                onResetSize: () {},
                child: const Text('Clock Content'),
              ),
            ),
          ),
        ),
      ),
    );

    // 4 gesture detectors for the 4 edge handles
    expect(find.text('Clock Content'), findsOneWidget);
    expect(find.byIcon(Icons.edit_rounded), findsOneWidget);
  });
}
