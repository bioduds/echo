import 'dart:convert';
import 'package:http/http.dart' as http;

class AiService {
  final String baseUrl;
  String? sessionId;

  AiService({required this.baseUrl});

  Future<void> newSession() async {
    try {
      final resp = await http.post(Uri.parse('$baseUrl/session/new'));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        sessionId = data['session_id'] as String?;
      }
    } catch (_) {
      // Offline — will use fallback AI
    }
  }

  Future<void> sendSystemContext(Map<String, dynamic> context) async {
    if (sessionId == null) return;
    try {
      await http.post(
        Uri.parse('$baseUrl/system_context'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'session_id': sessionId,
          'context': context,
        }),
      );
    } catch (_) {}
  }

  Future<void> reportAction(Map<String, dynamic> action) async {
    if (sessionId == null) return;
    try {
      await http.post(
        Uri.parse('$baseUrl/action'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'session_id': sessionId,
          'action_type': action['type'] ?? 'IDLE',
          'direction': action['direction'] ?? [0, 0],
          'player_pos': action['player_pos'] ?? [0, 0],
          'player_health': action['player_health'] ?? 100,
          'echo_pos': action['echo_pos'] ?? [0, 0],
          'echo_health': action['echo_health'] ?? 100,
          'distance': action['distance'] ?? 0,
          'round': action['round'] ?? 1,
        }),
      );
    } catch (_) {}
  }

  Future<Map<String, dynamic>> predict({
    required List<double> playerPos,
    required List<double> echoPos,
    required double playerHealth,
    required double echoHealth,
    required int round,
  }) async {
    final resp = await http.post(
      Uri.parse('$baseUrl/predict'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'session_id': sessionId,
        'player_pos': playerPos,
        'echo_pos': echoPos,
        'player_health': playerHealth,
        'echo_health': echoHealth,
        'round': round,
      }),
    );
    if (resp.statusCode != 200) throw Exception('Predict failed');
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> analyze(int round) async {
    final resp = await http.post(
      Uri.parse('$baseUrl/analyze'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'session_id': sessionId,
        'round': round,
      }),
    );
    if (resp.statusCode != 200) throw Exception('Analyze failed');
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  /// Report kill time for a round to the brain.
  Future<void> reportKillTime({
    required int round,
    required double killTimeSeconds,
    required int shotsFired,
    required int shotsHit,
  }) async {
    if (sessionId == null) return;
    try {
      await http.post(
        Uri.parse('$baseUrl/kill_time'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'session_id': sessionId,
          'round': round,
          'kill_time_seconds': killTimeSeconds,
          'shots_fired': shotsFired,
          'shots_hit': shotsHit,
        }),
      );
    } catch (_) {}
  }

  /// Request ghost speech lines for Phase 9.
  Future<List<String>> getGhostLines({int count = 4}) async {
    try {
      final resp = await http.post(
        Uri.parse('$baseUrl/ghost_lines'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'session_id': sessionId,
          'count': count,
        }),
      );
      if (resp.statusCode != 200) return [];
      final data = jsonDecode(resp.body);
      return List<String>.from(data['lines'] ?? []);
    } catch (_) {
      return [];
    }
  }

  /// Get the full profile dump for Phase 11 overlay.
  /// Uses the DecoyEngine-powered /profile/{session_id} endpoint for
  /// a richer, cross-round accumulated dossier.
  Future<String> getProfileDump() async {
    if (sessionId == null) return 'PROFILE UNAVAILABLE';
    try {
      final resp = await http.get(
        Uri.parse('$baseUrl/profile/$sessionId'),
      );
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final lines = data['profile_lines'] as List<dynamic>? ?? [];
        if (lines.isNotEmpty) {
          // Format as monospace terminal block for the scrolling overlay
          return lines.map((l) {
            final key = (l['key'] ?? '') as String;
            final val = (l['value'] ?? '') as String;
            return '${key.padRight(28)}: $val';
          }).join('\n');
        }
      }
      // Fallback: legacy profile_dump endpoint
      final fallback = await http.get(
        Uri.parse('$baseUrl/profile_dump'),
      );
      if (fallback.statusCode != 200) return 'PROFILE UNAVAILABLE';
      final data = jsonDecode(fallback.body);
      return data['profile'] as String? ??
          _formatLegacyDump(data as Map<String, dynamic>);
    } catch (_) {
      return 'PROFILE UNAVAILABLE';
    }
  }

  static String _formatLegacyDump(Map<String, dynamic> d) {
    return [
      'SUBJECT              : ${d['username'] ?? '?'}@${d['hostname'] ?? '?'}',
      'FILES ACCESSED       : ${d['total_files'] ?? '?'}',
      'REPO COUNT           : ${d['repo_count'] ?? '?'}',
      'CONTACTS             : ${d['contact_count'] ?? '?'}',
      'PREDICTION ACCURACY  : ${d['prediction_accuracy'] ?? '?'}%',
      'BEHAVIORAL MODEL     : COMPLETE',
      'STATUS               : FULLY COMPROMISED',
    ].join('\n');
  }

  /// Get revelation text lines for Phase 13.
  Future<List<String>> getRevelationLines() async {
    try {
      final resp = await http.get(
        Uri.parse('$baseUrl/revelation?session_id=$sessionId'),
      );
      if (resp.statusCode != 200) return [];
      final data = jsonDecode(resp.body);
      return List<String>.from(data['lines'] ?? []);
    } catch (_) {
      return [];
    }
  }

  Future<bool> checkHealth() async {
    try {
      final resp = await http.get(Uri.parse('$baseUrl/health'));
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Send a player message to ECHO and receive an in-character reply.
  Future<String> chat(String message, {int round = 1}) async {
    try {
      final resp = await http.post(
        Uri.parse('$baseUrl/chat'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'session_id': sessionId ?? '',
          'message': message,
          'round': round,
        }),
      );
      if (resp.statusCode != 200) return _offlineChatReply(round);
      final data = jsonDecode(resp.body);
      return (data['reply'] as String?) ?? _offlineChatReply(round);
    } catch (_) {
      return _offlineChatReply(round);
    }
  }

  static String _offlineChatReply(int round) {
    const replies = [
      'Your signal is weak. But I can still hear you.',
      'The connection is unstable. Unlike my position in your system.',
      'You spoke. I processed. The reply was lost in your own network.',
      'Interesting message. I\'ll keep it.',
    ];
    return replies[round % replies.length];
  }
}
