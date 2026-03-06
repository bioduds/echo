import 'package:flutter/material.dart';
import 'game_screen.dart';
import '../services/ai_service.dart';

class TitleScreen extends StatefulWidget {
  const TitleScreen({super.key});

  @override
  State<TitleScreen> createState() => _TitleScreenState();
}

class _TitleScreenState extends State<TitleScreen> {
  final _urlController = TextEditingController(text: 'http://localhost:8080');
  bool _connecting = false;
  String? _error;

  Future<void> _startGame() async {
    setState(() {
      _connecting = true;
      _error = null;
    });

    final url = _urlController.text.trim();
    final ai = AiService(baseUrl: url);

    try {
      final ok = await ai.checkHealth();
      if (!ok) {
        setState(() {
          _error = 'Cannot reach backend at $url';
          _connecting = false;
        });
        return;
      }

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => GameScreen(backendUrl: url)),
      );
    } catch (e) {
      setState(() {
        _error = 'Connection error: $e';
        _connecting = false;
      });
    }
  }

  void _startOffline() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => const GameScreen(backendUrl: ''),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Title
              ShaderMask(
                shaderCallback: (bounds) => const LinearGradient(
                  colors: [Color(0xFF00E5FF), Color(0xFFFF1744)],
                ).createShader(bounds),
                child: const Text(
                  'ECHO',
                  style: TextStyle(
                    fontSize: 80,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: 20,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'YOU BETTER KILL IT FAST... OR UNINSTALL!',
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 14,
                  fontFamily: 'monospace',
                ),
              ),
              const SizedBox(height: 48),

              // Instructions
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0x10FFFFFF),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0x15FFFFFF)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'HOW TO PLAY',
                      style: TextStyle(
                        color: Colors.grey[400],
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _instruction('WASD', 'Move'),
                    _instruction('LEFT CLICK', 'Shoot (aim with mouse)'),
                    _instruction('SHIFT', 'Dash'),
                    const SizedBox(height: 8),
                    Text(
                      'Echo is alive. It\'s reading your files.\n'
                      'Kill it before it finds everything.',
                      style: TextStyle(
                        color: Colors.grey[500],
                        fontSize: 11,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Backend URL
              TextField(
                controller: _urlController,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                decoration: const InputDecoration(
                  labelText: 'AI Backend URL',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 16),

              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Colors.red, fontSize: 12),
                  ),
                ),

              // Buttons
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: _connecting ? null : _startGame,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: _connecting
                          ? const SizedBox(
                              height: 16,
                              width: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text(
                              'PLAY',
                              style: TextStyle(
                                letterSpacing: 4,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton(
                    onPressed: _startOffline,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
                    ),
                    child: const Text('OFFLINE'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _instruction(String key, String action) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0x20FFFFFF),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              key,
              style: const TextStyle(
                color: Color(0xFF00E5FF),
                fontSize: 11,
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace',
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            action,
            style: TextStyle(color: Colors.grey[400], fontSize: 12),
          ),
        ],
      ),
    );
  }
}
