import 'dart:async';
import 'package:flutter/material.dart';
import 'title_screen.dart';

/// Full-screen disclaimer that must be accepted before playing.
/// 10-second forced read timer. No skip.
class DisclaimerScreen extends StatefulWidget {
  const DisclaimerScreen({super.key});

  @override
  State<DisclaimerScreen> createState() => _DisclaimerScreenState();
}

class _DisclaimerScreenState extends State<DisclaimerScreen> {
  int _countdown = 10;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_countdown > 0) {
        setState(() => _countdown--);
      } else {
        t.cancel();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _accept() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const TitleScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canAccept = _countdown <= 0;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Padding(
            padding: const EdgeInsets.all(40),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Warning icon
                const Icon(
                  Icons.warning_amber_rounded,
                  color: Color(0xFFFF1744),
                  size: 64,
                ),
                const SizedBox(height: 24),

                // Header
                const Text(
                  'THIS SOFTWARE WILL ACCESS YOUR SYSTEM',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFFFF1744),
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2,
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(height: 32),

                // Body
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: const Color(0x15FFFFFF),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: const Color(0x30FF1744),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _bullet(
                        'This game contains an AI that will scan your files, '
                        'documents, network activity, and system metadata as '
                        'part of the gameplay experience.',
                      ),
                      const SizedBox(height: 12),
                      _bullet(
                        'The AI will use this information to build a behavioral '
                        'profile of you.',
                      ),
                      const SizedBox(height: 12),
                      _bullet(
                        'At the end of the experience, you will be presented '
                        'with a negotiation. You may choose to pay or decline. '
                        'There is no penalty for declining.',
                      ),
                      const SizedBox(height: 12),
                      _bullet(
                        'All scanned data remains local on your machine. '
                        'Nothing is uploaded.',
                      ),
                      const SizedBox(height: 12),
                      _bullet(
                        'By proceeding, you consent to all of the above.',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),

                // Accept button (locked for 10 seconds)
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    child: FilledButton(
                      onPressed: canAccept ? _accept : null,
                      style: FilledButton.styleFrom(
                        backgroundColor: canAccept
                            ? const Color(0xFFFF1744)
                            : const Color(0x30FF1744),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: Text(
                        canAccept
                            ? 'I UNDERSTAND AND ACCEPT'
                            : 'READ CAREFULLY... ($_countdown)',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 2,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 16),
                Text(
                  'You agreed to this. Remember that.',
                  style: TextStyle(
                    color: Colors.grey[700],
                    fontSize: 11,
                    fontStyle: FontStyle.italic,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _bullet(String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '• ',
          style: TextStyle(
            color: Color(0xFFFF1744),
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: Color(0xCCFFFFFF),
              fontSize: 13,
              height: 1.5,
              fontFamily: 'monospace',
            ),
          ),
        ),
      ],
    );
  }
}
