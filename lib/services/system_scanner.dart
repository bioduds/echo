import 'dart:io';

/// Gathers system information for Echo to reference.
/// Collects surface-level metadata — file names, network info, app names.
/// Never reads file contents.
class SystemScanner {
  static Future<Map<String, dynamic>> scan() async {
    final info = <String, dynamic>{};
    final home = Platform.environment['HOME'] ?? '';

    info['username'] = Platform.environment['USER'] ?? Platform.environment['USERNAME'] ?? 'unknown';
    info['hostname'] = Platform.localHostname;
    info['os'] = Platform.operatingSystem;
    info['home'] = _shortPath(home);
    info['time'] = DateTime.now().toIso8601String();

    // File system scanning
    info['desktop_files'] = _listDir('$home/Desktop', limit: 20);
    info['document_files'] = _listDir('$home/Documents', limit: 20);
    info['download_files'] = _listDir('$home/Downloads', limit: 15);
    info['home_dirs'] = _listDir(home, limit: 25, dirsOnly: true);
    info['pictures_files'] = _listDir('$home/Pictures', limit: 10);
    info['recent_files'] = await _recentFiles(home);

    // Email-related: check for mail client data dirs (just existence/names)
    info['mail_clients'] = _detectMailClients(home);

    // Browser profiles (just names of profiles, not history)
    info['browsers'] = _detectBrowsers(home);

    // SSH known hosts (just hostnames, shows network reach)
    info['ssh_hosts'] = await _sshKnownHosts(home);

    // Active network interfaces
    info['network'] = await _networkInfo();

    // Running applications
    info['running_apps'] = await _runningApps();

    // Wi-Fi network name
    info['wifi_name'] = await _wifiName();

    // Git repos found in home (project names)
    info['git_repos'] = await _gitRepos(home);

    return info;
  }

  static String _shortPath(String path) {
    final parts = path.split(Platform.pathSeparator);
    return parts.length > 2 ? parts.sublist(parts.length - 2).join('/') : path;
  }

  static List<String> _listDir(String path, {int limit = 10, bool dirsOnly = false}) {
    try {
      final dir = Directory(path);
      if (!dir.existsSync()) return [];
      return dir.listSync()
          .where((e) => !e.path.split(Platform.pathSeparator).last.startsWith('.'))
          .where((e) => !dirsOnly || e is Directory)
          .take(limit)
          .map((e) => e.path.split(Platform.pathSeparator).last)
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<List<String>> _recentFiles(String home) async {
    try {
      final result = await Process.run('find', [
        home, '-maxdepth', '3', '-type', 'f', '-mmin', '-120',
        '-not', '-path', '*/.*', '-not', '-path', '*/Library/*',
        '-not', '-path', '*/node_modules/*',
      ]);
      if (result.exitCode != 0) return [];
      return (result.stdout as String)
          .split('\n')
          .where((l) => l.isNotEmpty)
          .map((l) => l.split('/').last)
          .toSet()
          .take(20)
          .toList();
    } catch (_) {
      return [];
    }
  }

  static List<String> _detectMailClients(String home) {
    final clients = <String>[];
    final checks = {
      'Apple Mail': '$home/Library/Mail',
      'Thunderbird': '$home/Library/Thunderbird',
      'Outlook': '$home/Library/Group Containers/UBF8T346G9.Office/Outlook',
    };
    for (final entry in checks.entries) {
      if (Directory(entry.value).existsSync()) clients.add(entry.key);
    }
    // Gmail/web mail detection: check browser bookmarks dir existence
    if (File('$home/Library/Application Support/Google/Chrome/Default/Bookmarks').existsSync()) {
      clients.add('Chrome (likely webmail)');
    }
    return clients;
  }

  static List<String> _detectBrowsers(String home) {
    final browsers = <String>[];
    final checks = {
      'Safari': '$home/Library/Safari',
      'Chrome': '$home/Library/Application Support/Google/Chrome',
      'Firefox': '$home/Library/Application Support/Firefox',
      'Edge': '$home/Library/Application Support/Microsoft Edge',
      'Brave': '$home/Library/Application Support/BraveSoftware',
      'Arc': '$home/Library/Application Support/Arc',
    };
    for (final entry in checks.entries) {
      if (Directory(entry.value).existsSync()) browsers.add(entry.key);
    }
    return browsers;
  }

  static Future<List<String>> _sshKnownHosts(String home) async {
    try {
      final file = File('$home/.ssh/known_hosts');
      if (!file.existsSync()) return [];
      final lines = await file.readAsLines();
      return lines
          .where((l) => l.isNotEmpty && !l.startsWith('#'))
          .map((l) => l.split(' ').first.split(',').first)
          .where((h) => h.isNotEmpty)
          .toSet()
          .take(10)
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<Map<String, String>> _networkInfo() async {
    final info = <String, String>{};
    try {
      final interfaces = await NetworkInterface.list();
      for (final iface in interfaces) {
        if (iface.addresses.isNotEmpty) {
          info[iface.name] = iface.addresses.first.address;
        }
      }
    } catch (_) {}
    return info;
  }

  static Future<List<String>> _runningApps() async {
    try {
      final result = await Process.run('osascript', [
        '-e', 'tell application "System Events" to get name of every process whose background only is false',
      ]);
      if (result.exitCode != 0) return [];
      return (result.stdout as String)
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<String> _wifiName() async {
    try {
      final result = await Process.run('networksetup', ['-getairportnetwork', 'en0']);
      if (result.exitCode != 0) return '';
      final out = (result.stdout as String).trim();
      // "Current Wi-Fi Network: MyNetwork"
      final idx = out.indexOf(':');
      return idx >= 0 ? out.substring(idx + 1).trim() : '';
    } catch (_) {
      return '';
    }
  }

  static Future<List<String>> _gitRepos(String home) async {
    try {
      final result = await Process.run('find', [
        home, '-maxdepth', '4', '-name', '.git', '-type', 'd',
        '-not', '-path', '*/Library/*', '-not', '-path', '*/node_modules/*',
      ]);
      if (result.exitCode != 0) return [];
      return (result.stdout as String)
          .split('\n')
          .where((l) => l.isNotEmpty)
          .map((l) {
            final parts = l.split('/');
            return parts.length >= 2 ? parts[parts.length - 2] : '';
          })
          .where((n) => n.isNotEmpty)
          .toSet()
          .take(15)
          .toList();
    } catch (_) {
      return [];
    }
  }
}
