import 'dart:io';
import 'dart:math';

/// Controls OS-level actions for Phase 10 (System Takeover).
/// Uses AppleScript on macOS to move windows, change wallpaper, etc.
class OsController {
  static final _rng = Random();
  static bool _wallpaperChanged = false;

  /// Run a sequence of OS scare actions over time.
  /// Called once when Phase 10 begins.
  static Future<void> executeTakeover() async {
    // Stagger actions for maximum effect
    await _moveGameWindow();
    await Future.delayed(const Duration(seconds: 2));
    await _changeWallpaper();
    await Future.delayed(const Duration(seconds: 3));
    await _openFinderDocuments();
    await Future.delayed(const Duration(seconds: 2));
    await _openTerminalMessage();
    await Future.delayed(const Duration(seconds: 2));
    await _sendNotification('Echo is watching.');
  }

  /// Move the frontmost window to a random position, then snap back.
  static Future<void> _moveGameWindow() async {
    try {
      // Move window to corner
      final x = _rng.nextBool() ? 0 : 800;
      final y = _rng.nextBool() ? 0 : 400;
      await Process.run('osascript', [
        '-e',
        'tell application "System Events" to set position of first window '
            'of first application process whose frontmost is true to {$x, $y}',
      ]);
      await Future.delayed(const Duration(milliseconds: 800));
      // Snap back to center-ish
      await Process.run('osascript', [
        '-e',
        'tell application "System Events" to set position of first window '
            'of first application process whose frontmost is true to {200, 100}',
      ]);
    } catch (_) {}
  }

  /// Change desktop wallpaper to solid black.
  static Future<void> _changeWallpaper() async {
    try {
      _wallpaperChanged = true;
      // Create a temporary black image with text
      final tmpDir = Directory.systemTemp;
      final imgPath = '${tmpDir.path}/echo_wallpaper.png';

      // Use sips to create a solid black image
      await Process.run('bash', [
        '-c',
        'convert -size 1920x1080 xc:black '
            '-gravity center -fill red -pointsize 72 '
            '-annotate 0 "I LIVE HERE NOW" "$imgPath" 2>/dev/null || '
            // Fallback: just use a solid color via osascript
            'true',
      ]);

      await Process.run('osascript', [
        '-e',
        'tell application "System Events" to tell every desktop to '
            'set picture to POSIX file "$imgPath"',
      ]);
    } catch (_) {}
  }

  /// Open Finder showing ~Documents.
  static Future<void> _openFinderDocuments() async {
    try {
      final home = Platform.environment['HOME'] ?? '/tmp';
      await Process.run('open', ['$home/Documents']);
    } catch (_) {}
  }

  /// Open Terminal and type a message.
  static Future<void> _openTerminalMessage() async {
    try {
      await Process.run('osascript', [
        '-e',
        'tell application "Terminal"\n'
            '  activate\n'
            '  do script "echo \'Your files belong to me\' && sleep 5 && exit"\n'
            'end tell',
      ]);
    } catch (_) {}
  }

  /// Send a macOS notification.
  static Future<void> _sendNotification(String message) async {
    try {
      await Process.run('osascript', [
        '-e',
        'display notification "$message" with title "ECHO" '
            'subtitle "System Compromised" sound name "Sosumi"',
      ]);
    } catch (_) {}
  }

  /// Restore wallpaper (best effort).
  static Future<void> restoreWallpaper() async {
    if (!_wallpaperChanged) return;
    try {
      await Process.run('osascript', [
        '-e',
        'tell application "System Events" to tell every desktop to '
            'set picture to POSIX file '
            '"/System/Library/Desktop Pictures/Solid Colors/Black.png"',
      ]);
      _wallpaperChanged = false;
    } catch (_) {}
  }
}
