import 'package:flutter/material.dart';
import 'package:flame/game.dart';
import '../game/echo_game.dart';

class GameScreen extends StatefulWidget {
  final String backendUrl;
  const GameScreen({super.key, required this.backendUrl});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  late EchoGame _game;

  @override
  void initState() {
    super.initState();
    _game = EchoGame(backendUrl: widget.backendUrl);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GameWidget(
        game: _game,
        overlayBuilderMap: {
          'round_end': (ctx, game) => _RoundEndOverlay(game: game as EchoGame),
        },
      ),
    );
  }
}

class _RoundEndOverlay extends StatelessWidget {
  final EchoGame game;
  const _RoundEndOverlay({required this.game});

  @override
  Widget build(BuildContext context) {
    final won = game.playerWonRound;
    final color = won ? const Color(0xFF00E5FF) : const Color(0xFFFF1744);
    final title = won ? 'ROUND ${game.round} WON' : 'ROUND ${game.round} LOST';

    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500),
        margin: const EdgeInsets.all(40),
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: const Color(0xF0101418),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withAlpha(80), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: color.withAlpha(30),
              blurRadius: 40,
              spreadRadius: 10,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Result
            Text(
              title,
              style: TextStyle(
                color: color,
                fontSize: 28,
                fontWeight: FontWeight.w900,
                letterSpacing: 4,
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(height: 24),

            // AI taunt
            if (game.aiTaunt != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF1744).withAlpha(15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: const Color(0xFFFF1744).withAlpha(40),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'ECHO SAYS:',
                      style: TextStyle(
                        color: Color(0xFFFF1744),
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '"${game.aiTaunt}"',
                      style: const TextStyle(
                        color: Color(0xCCFF1744),
                        fontSize: 14,
                        fontStyle: FontStyle.italic,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Behavior profile
            if (game.behaviorProfile != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0x10FFFFFF),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text(
                          'BEHAVIORAL ANALYSIS',
                          style: TextStyle(
                            color: Color(0x80FFFFFF),
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 2,
                          ),
                        ),
                        if (game.echoPlaystyle != null) ...[
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: color.withAlpha(30),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              game.echoPlaystyle!.toUpperCase(),
                              style: TextStyle(
                                color: color,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      game.behaviorProfile!,
                      style: const TextStyle(
                        color: Color(0x99FFFFFF),
                        fontSize: 13,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],

            // Tip
            Text(
              won
                  ? 'The Echo adapts. Can you keep changing?'
                  : 'Try changing your patterns. The Echo predicted you.',
              style: TextStyle(
                color: Colors.grey[500],
                fontSize: 12,
                fontStyle: FontStyle.italic,
              ),
            ),
            const SizedBox(height: 20),

            // Continue button
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: game.startNextRound,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  backgroundColor: color.withAlpha(40),
                  foregroundColor: color,
                ),
                child: Text(
                  'ROUND ${game.round + 1} →',
                  style: const TextStyle(
                    letterSpacing: 3,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
