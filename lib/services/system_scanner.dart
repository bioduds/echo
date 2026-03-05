import 'dart:io';

/// Gathers innocuous but creepy system information for Echo to reference.
/// Only collects surface-level metadata — never reads file contents.
class SystemScanner {
  static Future<Map<String, dynamic>> scan() async {
    final info = <String, dynamic>{};

    info['username'] = Platform.environment['USER'] ?? Platform.environment['USERNAME'] ?? 'unknown';
    info['hostname'] = Platform.localHostname;
    info['os'] = Platform.operatingSystem;
    info['home'] = _shortPath(Platform.environment['HOME'] ?? '');
    info['time'] = DateTime.now().toIso8601String();
    info['dart_version'] = Platform.version.split(' ').first;

    // Desktop files (just names, never contents)
    info['desktop_files'] = _listDir(_desktopPath(), limit: 15);

    // Documents folder (just names)
    info['document_files'] = _listDir(_documentsPath(), limit: 15);

    // Downloads folder (recent names)
    info['download_files'] = _listDir(_downloadsPath(), limit: 10);

    // Home directory top-level
    final home = Platform.environment['HOME'] ?? '';
    info['home_dirs'] = _listDir(home, limit: 20, dirsOnly: true);

    // Recently modified files in home (last 2 hours)
    info['recent_files'] = await _recentFiles(home);

    return info;
  }

  static String _shortPath(String path) {
    // Just the last 2 components
    final parts = path.split(Platform.pathSeparator);
    return parts.length > 2 ? parts.sublist(parts.length - 2).join('/') : path;
  }

  static String _desktopPath() {
    final home = Platform.environment['HOME'] ?? '';
    return '$home/Desktop';
  }

  static String _documentsPath() {
    final home = Platform.environment['HOME'] ?? '';
    return '$home/Documents';
  }

  static String _downloadsPath() {
    final home = Platform.environment['HOME'] ?? '';
    return '$home/Downloads';
  }

  static List<String> _listDir(String path, {int limit = 10, bool dirsOnly = false}) {
    try {
      final dir = Directory(path);
      if (!dir.existsSync()) return [];
      final entries = dir.listSync()
          .where((e) => !e.path.split(Platform.pathSeparator).last.startsWith('.'))
          .where((e) => !dirsOnly || e is Directory)
          .take(limit)
          .map((e) => e.path.split(Platform.pathSeparator).last)
          .toList();
      return entries;
    } catch (_) {
      return [];
    }
  }

  static Future<List<String>> _recentFiles(String home) async {
    try {
      // Find files modified in last 2 hours, just names
      final result = await Process.run('find', [
        home,
        '-maxdepth', '3',
        '-type', 'f',
        '-mmin', '-120',
        '-not', '-path', '*/.*',
        '-not', '-path', '*/Library/*',
        '-not', '-path', '*/node_modules/*',
      ]);
      if (result.exitCode != 0) return [];
      final lines = (result.stdout as String)
          .split('\n')
          .where((l) => l.isNotEmpty)
          .map((l) => l.split('/').last)
          .toSet() // deduplicate
          .take(15)
          .toList();
      return lines;
    } catch (_) {
      return [];
    }
  }
}
