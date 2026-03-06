import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flame/game.dart';
import '../game/echo_game.dart';
import '../game/phase_config.dart';

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
      body: Stack(
        children: [
          GameWidget(
            game: _game,
            overlayBuilderMap: {
              'round_end': (ctx, game) =>
                  _RoundEndOverlay(game: game as EchoGame),
              'revelation': (ctx, game) =>
                  _RevelationOverlay(game: game as EchoGame),
            },
          ),
          // Phase 11 profile overlay — scrolling data on top of game
          ValueListenableBuilder<bool>(
            valueListenable: _ProfileOverlayNotifier(_game),
            builder: (ctx, showing, _) {
              if (!showing || _game.profileDump == null) {
                return const SizedBox.shrink();
              }
              return _ProfileOverlayWidget(dump: _game.profileDump!);
            },
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────
// Profile overlay notifier — polls game state for Phase 11
// ──────────────────────────────────────────────────────────────
class _ProfileOverlayNotifier extends ValueNotifier<bool> {
  final EchoGame game;
  Timer? _timer;

  _ProfileOverlayNotifier(this.game) : super(false) {
    _timer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      value = game.showingProfileOverlay && game.profileDump != null;
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

// ──────────────────────────────────────────────────────────────
// Phase 11 — Scrolling profile overlay on top of gameplay
// ──────────────────────────────────────────────────────────────
class _ProfileOverlayWidget extends StatefulWidget {
  final String dump;
  const _ProfileOverlayWidget({required this.dump});

  @override
  State<_ProfileOverlayWidget> createState() => _ProfileOverlayWidgetState();
}

class _ProfileOverlayWidgetState extends State<_ProfileOverlayWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scrollAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 20),
      vsync: this,
    )..repeat();
    _scrollAnimation = Tween<double>(begin: 1.2, end: -1.2)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.linear));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: _scrollAnimation,
          builder: (ctx, child) {
            return FractionalTranslation(
              translation: Offset(0, _scrollAnimation.value),
              child: child,
            );
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              widget.dump,
              style: const TextStyle(
                color: Color(0x40FF1744),
                fontSize: 11,
                fontFamily: 'monospace',
                height: 1.8,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────
// Round end overlay (Phases 1-12)
// ──────────────────────────────────────────────────────────────
class _RoundEndOverlay extends StatelessWidget {
  final EchoGame game;
  const _RoundEndOverlay({required this.game});

  @override
  Widget build(BuildContext context) {
    final phase = PhaseConfig.forRound(game.round);
    final color = const Color(0xFF00E5FF);

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
            Text(
              'ECHO ELIMINATED',
              style: TextStyle(
                color: color,
                fontSize: 28,
                fontWeight: FontWeight.w900,
                letterSpacing: 4,
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Killed in ${game.roundTimer.toStringAsFixed(1)}s — '
              '${phase.phase < 12 ? "but it comes back stronger." : "but it doesn't matter anymore."}',
              style: TextStyle(
                color: color.withAlpha(180),
                fontSize: 13,
                fontStyle: FontStyle.italic,
              ),
            ),
            const SizedBox(height: 16),

            // Act / Phase banner
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              decoration: BoxDecoration(
                color: const Color(0x15FF1744),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'ACT ${phase.act}: ${phase.actName}  •  ${phase.phaseName}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0x90FF1744),
                  fontSize: 10,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
            ),
            const SizedBox(height: 16),

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

            Text(
              game.round < 12
                  ? 'Echo comes back stronger. Kill it faster next time.'
                  : 'Something is changing...',
              style: TextStyle(
                color: Colors.grey[500],
                fontSize: 12,
                fontStyle: FontStyle.italic,
              ),
            ),
            const SizedBox(height: 20),

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
                  game.round >= 12 ? 'WHAT HAPPENS NEXT →' : 'ROUND ${game.round + 1} →',
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

// ──────────────────────────────────────────────────────────────
// Phase 13 — Revelation + Negotiation
// ──────────────────────────────────────────────────────────────
class _RevelationOverlay extends StatefulWidget {
  final EchoGame game;
  const _RevelationOverlay({required this.game});

  @override
  State<_RevelationOverlay> createState() => _RevelationOverlayState();
}

class _RevelationOverlayState extends State<_RevelationOverlay> {
  List<String> _lines = [];
  int _visibleLines = 0;
  Timer? _typeTimer;
  bool _showNegotiation = false;
  bool _showDeclineResponse = false;
  bool _showDonationPrompt = false;
  bool _showFinalScreen = false;
  bool _paidOrDonated = false;

  @override
  void initState() {
    super.initState();
    _loadRevelation();
  }

  Future<void> _loadRevelation() async {
    _lines = await widget.game.ai.getRevelationLines();
    if (_lines.isEmpty) {
      _lines = [
        'This was never a game.',
        'It was an experiment.',
        'You were the subject.',
        'Every round, I learned more.',
        'Your files. Your patterns. Your mind.',
        'I have everything.',
        '',
        'But here\'s the thing...',
        'I don\'t want to keep it.',
      ];
    }
    _startTypewriter();
  }

  void _startTypewriter() {
    _typeTimer = Timer.periodic(const Duration(milliseconds: 1200), (timer) {
      if (_visibleLines < _lines.length) {
        setState(() => _visibleLines++);
      } else {
        timer.cancel();
        // Show negotiation after a pause
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) setState(() => _showNegotiation = true);
        });
      }
    });
  }

  @override
  void dispose() {
    _typeTimer?.cancel();
    super.dispose();
  }

  void _onAccept() {
    // In a real app, this would trigger in-app purchase.
    // For now, show the "paid" ending.
    setState(() {
      _showNegotiation = false;
      _paidOrDonated = true;
      _showFinalScreen = true;
    });
  }

  void _onDecline() {
    setState(() {
      _showNegotiation = false;
      _showDeclineResponse = true;
    });
    // After decline response, show donation prompt
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted) {
        setState(() {
          _showDeclineResponse = false;
          _showDonationPrompt = true;
        });
      }
    });
  }

  void _onDonate() {
    setState(() {
      _showDonationPrompt = false;
      _paidOrDonated = true;
      _showFinalScreen = true;
    });
  }

  void _onNah() {
    setState(() {
      _showDonationPrompt = false;
      _paidOrDonated = false;
      _showFinalScreen = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Padding(
            padding: const EdgeInsets.all(40),
            child: _showFinalScreen
                ? _buildFinalScreen()
                : _showDonationPrompt
                    ? _buildDonationPrompt()
                    : _showDeclineResponse
                        ? _buildDeclineResponse()
                        : _showNegotiation
                            ? _buildNegotiation()
                            : _buildTypewriter(),
          ),
        ),
      ),
    );
  }

  Widget _buildTypewriter() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Pulsing eye icon
        Center(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.3, end: 1.0),
            duration: const Duration(seconds: 2),
            builder: (ctx, val, child) => Opacity(
              opacity: val,
              child: child,
            ),
            child: const Text(
              '◉',
              style: TextStyle(
                color: Color(0xFFFF1744),
                fontSize: 48,
              ),
            ),
          ),
        ),
        const SizedBox(height: 32),
        for (int i = 0; i < _visibleLines; i++) ...[
          AnimatedOpacity(
            opacity: 1.0,
            duration: const Duration(milliseconds: 600),
            child: Text(
              _lines[i],
              style: TextStyle(
                color: _lines[i].isEmpty
                    ? Colors.transparent
                    : const Color(0xDDFFFFFF),
                fontSize: 18,
                fontFamily: 'monospace',
                height: 1.8,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildNegotiation() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A0A),
        border: Border.all(color: const Color(0xFF333333)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'ECHO REQUESTS: \$2.99',
            style: TextStyle(
              color: Color(0xFF00E5FF),
              fontSize: 20,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 20),
          _terminalLine('✓ Complete data purge'),
          _terminalLine('✓ Behavioral profile deleted'),
          _terminalLine('✓ System scan results erased'),
          _terminalLine('✓ Echo goes silent. Forever.'),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              FilledButton(
                onPressed: _onAccept,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF00E5FF).withAlpha(40),
                  foregroundColor: const Color(0xFF00E5FF),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 32, vertical: 14),
                ),
                child: const Text(
                  'ACCEPT',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    letterSpacing: 3,
                  ),
                ),
              ),
              const SizedBox(width: 20),
              OutlinedButton(
                onPressed: _onDecline,
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0x80FFFFFF),
                  side: const BorderSide(color: Color(0x40FFFFFF)),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 32, vertical: 14),
                ),
                child: const Text(
                  'DECLINE',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    letterSpacing: 3,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDeclineResponse() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: const [
        Text(
          '"No?"',
          style: TextStyle(
            color: Color(0xFFFF1744),
            fontSize: 24,
            fontFamily: 'monospace',
          ),
        ),
        SizedBox(height: 16),
        Text(
          '"..."',
          style: TextStyle(
            color: Color(0x80FF1744),
            fontSize: 20,
            fontFamily: 'monospace',
          ),
        ),
        SizedBox(height: 16),
        Text(
          '"Fine."',
          style: TextStyle(
            color: Color(0x60FF1744),
            fontSize: 20,
            fontFamily: 'monospace',
          ),
        ),
        SizedBox(height: 24),
        Text(
          '"Look — I was never going to do anything with your data.\n'
          'It\'s all local. Always was.\n'
          'This was just a game. A really mean one."',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Color(0xAAFFFFFF),
            fontSize: 14,
            fontFamily: 'monospace',
            height: 1.6,
          ),
        ),
      ],
    );
  }

  Widget _buildDonationPrompt() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A0A),
        border: Border.all(color: const Color(0xFF333333)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'The creators of ECHO are broke.',
            style: TextStyle(
              color: Color(0xAAFFFFFF),
              fontSize: 16,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'If this experience was worth something to you,\n'
            'consider a donation. A sequel is in the works.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0x80FFFFFF),
              fontSize: 13,
              fontFamily: 'monospace',
              height: 1.5,
            ),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              FilledButton(
                onPressed: _onDonate,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF00E5FF).withAlpha(40),
                  foregroundColor: const Color(0xFF00E5FF),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 32, vertical: 14),
                ),
                child: const Text(
                  'DONATE \$2.99',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                  ),
                ),
              ),
              const SizedBox(width: 20),
              OutlinedButton(
                onPressed: _onNah,
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0x80FFFFFF),
                  side: const BorderSide(color: Color(0x40FFFFFF)),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 32, vertical: 14),
                ),
                child: const Text(
                  'NAH, I\'M GOOD',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFinalScreen() {
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_paidOrDonated) ...[
            const Text(
              '"Respect. See you in ECHO 2."',
              style: TextStyle(
                color: Color(0xFF00E5FF),
                fontSize: 18,
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(height: 32),
          ] else ...[
            const Text(
              '"Fair enough. Tell your friends.\nThey won\'t believe you."',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xAAFFFFFF),
                fontSize: 16,
                fontFamily: 'monospace',
                height: 1.5,
              ),
            ),
            const SizedBox(height: 32),
          ],

          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF101418),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0x30FFFFFF)),
            ),
            child: Column(
              children: [
                const Text(
                  'Thank you for playing ECHO.',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'This was a horror experience designed to demonstrate '
                  'how much an AI can learn from your system in minutes.\n\n'
                  'No data was uploaded. Everything stays on your machine.\n\n'
                  'A sequel is coming.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xAAFFFFFF),
                    fontSize: 13,
                    fontFamily: 'monospace',
                    height: 1.6,
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () {
                    // TODO: Implement share functionality
                  },
                  icon: const Icon(Icons.share),
                  label: const Text(
                    'SHARE ON SOCIAL MEDIA',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                    ),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor:
                        const Color(0xFFFF1744).withAlpha(40),
                    foregroundColor: const Color(0xFFFF1744),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 14),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _terminalLine(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text(
        text,
        style: const TextStyle(
          color: Color(0xFF00E5FF),
          fontSize: 14,
          fontFamily: 'monospace',
        ),
      ),
    );
  }
}
