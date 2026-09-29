class TaskQueue {
  final int maxConcurrent;
  int _running = 0;
  final List<Function> _queue = [];

  TaskQueue({this.maxConcurrent = 3});

  Future<T> run<T>(Future<T> Function() task) {
    // ...
  }
}
