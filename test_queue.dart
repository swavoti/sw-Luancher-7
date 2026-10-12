import 'dart:async';

class TaskQueue {
  final int maxConcurrent;
  int _running = 0;
  final List<Function> _queue = [];

  TaskQueue({this.maxConcurrent = 3});

  Future<T> run<T>(Future<T> Function() task) {
    final completer = Completer<T>();

    void start() {
      _running++;
      Future<T>.sync(task)
          .then(completer.complete)
          .catchError((Object error, StackTrace stackTrace) {
            completer.completeError(error, stackTrace);
          })
          .whenComplete(() {
            _running--;
            _pump();
          });
    }

    if (_running < maxConcurrent) {
      start();
    } else {
      _queue.add(start);
    }

    return completer.future;
  }

  void _pump() {
    while (_running < maxConcurrent && _queue.isNotEmpty) {
      final next = _queue.removeAt(0) as void Function();
      next();
    }
  }
}
