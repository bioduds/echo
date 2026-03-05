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

  Future<bool> checkHealth() async {
    try {
      final resp = await http.get(Uri.parse('$baseUrl/health'));
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
