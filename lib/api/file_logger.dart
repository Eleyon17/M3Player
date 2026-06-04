import 'dart:io';

class FileLogger {
  static final File _logFile = File('/tmp/m3p_flutter_log.txt');
  
  static void log(String message) {
    try {
      final time = DateTime.now().toIso8601String();
      _logFile.writeAsStringSync('[$time] $message\n', mode: FileMode.append);
      print('[$time] $message');
    } catch (_) {}
  }

  static void clear() {
    try {
      if (_logFile.existsSync()) {
        _logFile.deleteSync();
      }
    } catch (_) {}
  }
}
