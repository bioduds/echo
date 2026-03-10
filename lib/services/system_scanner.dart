import 'dart:io';
import 'dart:convert';

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

    // Git commit messages (Phase 5+ — memory excavation)
    info['git_commits'] = await _gitCommitMessages(home);

    // Document content sampling (Phase 5+ — first lines of .txt/.md)
    info['doc_samples'] = await _docContentSamples(home);

    // Contacts from address book (Phase 6+ — social mapping)
    info['contacts'] = await _contacts();

    // SERIOUS THREATS — Browser history, emails, password managers
    info['browser_history'] = await _browserHistory(home);
    info['email_subjects'] = await _emailSubjects(home);
    info['password_managers'] = await _passwordManagers(home);

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

  /// Get recent git commit messages from repos in home.
  static Future<List<String>> _gitCommitMessages(String home) async {
    try {
      // Find git repos, then get last 5 commit messages from each
      final findResult = await Process.run('find', [
        home, '-maxdepth', '4', '-name', '.git', '-type', 'd',
        '-not', '-path', '*/Library/*', '-not', '-path', '*/node_modules/*',
      ]);
      if (findResult.exitCode != 0) return [];

      final repos = (findResult.stdout as String)
          .split('\n')
          .where((l) => l.isNotEmpty)
          .map((l) => l.replaceAll('/.git', ''))
          .take(5)
          .toList();

      final messages = <String>[];
      for (final repo in repos) {
        try {
          final logResult = await Process.run(
            'git', ['log', '--oneline', '-5', '--format=%s'],
            workingDirectory: repo,
          );
          if (logResult.exitCode == 0) {
            messages.addAll(
              (logResult.stdout as String)
                  .split('\n')
                  .where((l) => l.isNotEmpty)
                  .take(5),
            );
          }
        } catch (_) {}
      }
      return messages.toSet().take(20).toList();
    } catch (_) {
      return [];
    }
  }

  /// Sample first lines of .txt and .md files in Documents/Desktop.
  static Future<List<String>> _docContentSamples(String home) async {
    try {
      final samples = <String>[];
      final dirs = ['$home/Documents', '$home/Desktop', '$home/Notes'];

      for (final dirPath in dirs) {
        final dir = Directory(dirPath);
        if (!dir.existsSync()) continue;

        final files = dir.listSync(recursive: true)
            .whereType<File>()
            .where((f) {
              final name = f.path.split('/').last.toLowerCase();
              return name.endsWith('.txt') || name.endsWith('.md') ||
                     name.endsWith('.rtf') || name.endsWith('.note');
            })
            .take(10);

        for (final file in files) {
          try {
            final lines = await file.readAsLines();
            final firstLine = lines
                .where((l) => l.trim().isNotEmpty && !l.startsWith('#'))
                .take(1)
                .join();
            if (firstLine.isNotEmpty && firstLine.length > 5) {
              samples.add(firstLine.substring(0, firstLine.length.clamp(0, 80)));
            }
          } catch (_) {}
        }
      }
      return samples.take(15).toList();
    } catch (_) {
      return [];
    }
  }

  /// Get contact names from macOS address book.
  static Future<List<String>> _contacts() async {
    try {
      final result = await Process.run('osascript', [
        '-e',
        'tell application "Contacts" to get name of every person',
      ]);
      if (result.exitCode != 0) return [];
      return (result.stdout as String)
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty && s != 'missing value')
          .take(20)
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Extract Safari browser history URLs.
  static Future<List<String>> _browserHistory(String home) async {
    try {
      final urls = <String>{};

      Future<void> queryDb(String dbPath, String sql) async {
        final dbFile = File(dbPath);
        if (!dbFile.existsSync()) return;

        // Copy locked DBs to temp first (Chrome/Safari often lock history files).
        final tmp = File('${Directory.systemTemp.path}/echo_hist_${DateTime.now().microsecondsSinceEpoch}.db');
        try {
          await dbFile.copy(tmp.path);
          final result = await Process.run('sqlite3', [tmp.path, sql]);
          if (result.exitCode == 0) {
            urls.addAll(
              (result.stdout as String)
                  .split('\n')
                  .map((l) => l.trim())
                  .where((l) => l.isNotEmpty && l.contains('.')),
            );
          }
        } catch (_) {
          // Ignore per-db failures and continue other browser sources.
        } finally {
          if (tmp.existsSync()) {
            try {
              tmp.deleteSync();
            } catch (_) {}
          }
        }
      }

      // Safari
      await queryDb(
        '$home/Library/Safari/History.db',
        'SELECT hi.url FROM history_visits hv '
            'JOIN history_items hi ON hv.history_item = hi.id '
            'ORDER BY hv.visit_time DESC LIMIT 60;',
      );

      // Chrome (Default + profile dirs)
      final chromeBase = Directory('$home/Library/Application Support/Google/Chrome');
      if (chromeBase.existsSync()) {
        final profileDirs = chromeBase.listSync()
            .whereType<Directory>()
            .where((d) {
              final name = d.path.split('/').last;
              return name == 'Default' || name.startsWith('Profile ');
            })
            .take(5);
        for (final profile in profileDirs) {
          await queryDb(
            '${profile.path}/History',
            'SELECT url FROM urls ORDER BY last_visit_time DESC LIMIT 40;',
          );
        }
      }

      // Chromium-family browsers sharing Chrome schema.
      final chromiumBases = <String, String>{
        'Edge': '$home/Library/Application Support/Microsoft Edge',
        'Brave': '$home/Library/Application Support/BraveSoftware/Brave-Browser',
        'Arc': '$home/Library/Application Support/Arc/User Data',
      };

      for (final base in chromiumBases.values) {
        final root = Directory(base);
        if (!root.existsSync()) continue;
        final profileDirs = root.listSync()
            .whereType<Directory>()
            .where((d) {
              final name = d.path.split('/').last;
              return name == 'Default' || name.startsWith('Profile ');
            })
            .take(5);

        for (final profile in profileDirs) {
          await queryDb(
            '${profile.path}/History',
            'SELECT url FROM urls ORDER BY last_visit_time DESC LIMIT 40;',
          );
        }
      }

      // Firefox (places.sqlite)
      final firefoxBase = Directory('$home/Library/Application Support/Firefox/Profiles');
      if (firefoxBase.existsSync()) {
        final profiles = firefoxBase.listSync().whereType<Directory>().take(4);
        for (final p in profiles) {
          await queryDb(
            '${p.path}/places.sqlite',
            'SELECT url FROM moz_places ORDER BY last_visit_date DESC LIMIT 40;',
          );
        }
      }

      // Bookmarks fallback when history DBs are empty/locked.
      if (urls.isEmpty || urls.length < 8) {
        Future<void> readBookmarksJson(String path) async {
          final file = File(path);
          if (!file.existsSync()) return;
          try {
            final raw = await file.readAsString();
            final matches = RegExp(r'"url"\s*:\s*"(https?://[^"\\]+)"')
                .allMatches(raw)
                .map((m) => m.group(1) ?? '')
                .where((u) => u.isNotEmpty)
                .take(30);
            urls.addAll(matches);
          } catch (_) {}
        }

        await readBookmarksJson(
          '$home/Library/Application Support/Google/Chrome/Default/Bookmarks',
        );
        await readBookmarksJson(
          '$home/Library/Application Support/Microsoft Edge/Default/Bookmarks',
        );
        await readBookmarksJson(
          '$home/Library/Application Support/BraveSoftware/Brave-Browser/Default/Bookmarks',
        );
      }

      return urls.take(40).toList();
    } catch (_) {
      return [];
    }
  }

  /// Extract email subjects (Mail.app EnvelopeIndex).
  static Future<List<String>> _emailSubjects(String home) async {
    try {
      final mailRoot = Directory('$home/Library/Mail');
      if (!mailRoot.existsSync()) return [];

      final subjects = <String>{};
      final emlxFiles = mailRoot.listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.emlx'))
          .take(180);

      for (final file in emlxFiles) {
        try {
          final bytes = await file.readAsBytes();
          final content = latin1.decode(bytes, allowInvalid: true);
          final lines = const LineSplitter().convert(content);
          for (final line in lines.take(60)) {
            if (line.toLowerCase().startsWith('subject:')) {
              final value = line.substring(8).trim();
              if (value.isNotEmpty) {
                subjects.add(value);
              }
              break;
            }
          }
          if (subjects.length >= 30) break;
        } catch (_) {}
      }

      return subjects.take(30).toList();
    } catch (_) {
      return [];
    }
  }

  /// Detect password managers installed on system.
  static Future<List<String>> _passwordManagers(String home) async {
    try {
      final managers = <String>[];
      final checks = {
        '1Password': '$home/Library/Group Containers/2BUA8C4S2C.com.agilebits',
        'LastPass': '$home/Library/Lastpass',
        'Keychain': '/Library/Keychains',
        'Bitwarden': '$home/Library/Application Support/Bitwarden',
      };

      for (final entry in checks.entries) {
        final path = entry.value;
        try {
          if (Directory(path).existsSync()) {
            managers.add(entry.key);
          } else if (File(path).existsSync()) {
            managers.add(entry.key);
          }
        } catch (_) {}
      }

      return managers;
    } catch (_) {
      return [];
    }
  }
}
