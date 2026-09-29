cat << 'INNER_EOF' > fix_queue.py
import re
with open('lib/services/app_database_service.dart', 'r') as f:
    content = f.read()

queue_code = """
  static final List<void Function()> _taskQueue = [];
  static int _runningTasks = 0;
  static const int _maxConcurrentTasks = 2;

  static Future<T> _enqueue<T>(Future<T> Function() task) {
    import_async(); // Just a trick if dart:async is not imported. It is imported by dart:io/typed_data, wait, dart:async might be needed.
    final completer = Completer<T>();
    _taskQueue.add(() async {
      try {
        final result = await task();
        completer.complete(result);
      } catch (e) {
        completer.completeError(e);
      } finally {
        _runningTasks--;
        _pumpQueue();
      }
    });
    _pumpQueue();
    return completer.future;
  }

  static void _pumpQueue() {
    while (_runningTasks < _maxConcurrentTasks && _taskQueue.isNotEmpty) {
      _runningTasks++;
      final next = _taskQueue.removeAt(0);
      next();
    }
  }

  static Future<Database> get database async {"""

content = content.replace("  static Future<Database> get database async {", queue_code)
content = content.replace("import_async();", "")
if "import 'dart:async';" not in content:
    content = content.replace("import 'dart:typed_data';", "import 'dart:typed_data';\nimport 'dart:async';")

# Now replace the calls to getThemedIcon and getAppInfo
content = content.replace("await LauncherService.getThemedIcon(packageName, currentIconPack);", "await _enqueue(() => LauncherService.getThemedIcon(packageName, currentIconPack));")
content = content.replace("await InstalledApps.getAppInfo(packageName);", "await _enqueue(() => InstalledApps.getAppInfo(packageName));")

with open('lib/services/app_database_service.dart', 'w') as f:
    f.write(content)
INNER_EOF
python3 fix_queue.py
