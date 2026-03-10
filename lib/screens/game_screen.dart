import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flame/game.dart';
import '../game/echo_game.dart';
import '../game/phase_config.dart';
import '../services/payment_service.dart';

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
    // Enter fullscreen
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) {
          // Hide system UI for fullscreen effect
          _enterFullscreen();
        }
      });
    });
  }

  void _enterFullscreen() {
    // Hide overlay UI; desktop fullscreen is enforced in MainFlutterWindow.swift.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          GameWidget(
            game: _game,
            overlayBuilderMap: {
              'round_end': (ctx, game) =>
                  _RoundEndOverlay(game: game as EchoGame),
              'revelation': (ctx, game) =>
                  _RevelationOverlay(game: game as EchoGame),
              'chat': (ctx, game) =>
                  _ChatOverlay(game: game as EchoGame),
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
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 680),
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
        child: SingleChildScrollView(
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
  bool _showPurgeSequence = false;
  bool _showFinalScreen = false;
  bool _paidOrDonated = false;
  
  late PaymentService _paymentService;
  String? _paymentError;
  double _purgeProgress = 0.0;
  List<PurgeStage> _purgeStages = [];

  @override
  void initState() {
    super.initState();
    _paymentService = PaymentService(
      baseUrl: widget.game.backendUrl,
      sessionId: widget.game.sessionId,
    );
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
    _paymentService.dispose();
    super.dispose();
  }

  void _onAccept() async {
    // Initiate real in-app purchase
    setState(() => _paymentError = null);
    
    try {
      final txn = await _paymentService.initiatePayment();
      
      // Payment successful — show purge animation
      _showPurgeSequence = true;
      await _runPurgeAnimation();
      
      if (mounted) {
        setState(() {
          _showNegotiation = false;
          _paidOrDonated = true;
          _showFinalScreen = true;
        });
        _paymentService.recordPurchaseComplete(
          productId: txn.productId,
          amount: txn.amount,
        );
      }
    } on PaymentException catch (e) {
      if (mounted) {
        setState(() {
          _paymentError = e.message;
          // Keep showing negotiation, allow retry or decline
        });
      }
    }
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

  void _onDonate() async {
    // Initiate real donation purchase
    setState(() => _paymentError = null);
    
    try {
      final txn = await _paymentService.initiateDonation(amount: 'regular');
      
      // Donation successful
      if (mounted) {
        setState(() {
          _showDonationPrompt = false;
          _paidOrDonated = true;
          _showFinalScreen = true;
        });
        _paymentService.recordPurchaseComplete(
          productId: txn.productId,
          amount: txn.amount,
        );
      }
    } on PaymentException catch (e) {
      if (mounted) {
        setState(() {
          _paymentError = e.message;
          // Keep showing donation prompt, allow retry
        });
      }
    }
  }

  void _onNah() {
    setState(() {
      _showDonationPrompt = false;
      _paidOrDonated = false;
      _showFinalScreen = true;
    });
  }

  Future<void> _runPurgeAnimation() async {
    try {
      _purgeStages = await _paymentService.getPurgeSequence();
      
      for (int i = 0; i < _purgeStages.length; i++) {
        final stage = _purgeStages[i];
        
        // Wait for stage delay
        await Future.delayed(Duration(milliseconds: stage.delayMs));
        
        if (mounted) {
          setState(() {
            _purgeProgress = stage.progress;
          });
        }
      }
    } catch (e) {
      print('Purge animation error: $e');
      // Still proceed to final screen even if purge endpoint fails
      if (mounted) {
        setState(() {
          _purgeProgress = 1.0;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewportHeight = MediaQuery.of(context).size.height;

    return Container(
      color: Colors.black,
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 600,
            maxHeight: viewportHeight - 48,
          ),
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(40),
              child: _showFinalScreen
                  ? _buildFinalScreen()
                  : _showPurgeSequence
                      ? _buildPurgeSequence()
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
          
          // Show payment error if present
          if (_paymentError != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF1A0000),
                border: Border.all(color: const Color(0xFFFF1744)),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                _paymentError!,
                style: const TextStyle(
                  color: Color(0xFFFF1744),
                  fontSize: 12,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ],
          
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

  Widget _buildPurgeSequence() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Pulsing eye during purge
        Center(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.6, end: 1.0),
            duration: const Duration(seconds: 1),
            builder: (ctx, val, child) => Opacity(
              opacity: val,
              child: child,
            ),
            child: const Text(
              '◉',
              style: TextStyle(
                color: Color(0xFF00E5FF),
                fontSize: 48,
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        
        // Purge stage description
        const Text(
          'PURGING DATA...',
          style: TextStyle(
            color: Color(0xFF00E5FF),
            fontSize: 16,
            fontFamily: 'monospace',
            fontWeight: FontWeight.bold,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 20),
        
        // Progress bar
        Container(
          height: 8,
          width: double.infinity,
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: const Color(0xFF333333)),
          ),
          child: FractionallySizedBox(
            widthFactor: _purgeProgress,
            child: Container(
              decoration: BoxDecoration(
                color: Color.lerp(
                  const Color(0xFF00E5FF),
                  const Color(0xFF00FF00),
                  _purgeProgress,
                ),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        
        // Current stage label
        if (_purgeStages.isNotEmpty)
          Text(
            _purgeStages[
              (_purgeProgress * _purgeStages.length).floor().clamp(
                0,
                _purgeStages.length - 1,
              )
            ].label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xAAFFFFFF),
              fontSize: 12,
              fontFamily: 'monospace',
              height: 1.6,
            ),
          )
        else
          const Text(
            'Deleting traces...',
            style: TextStyle(
              color: Color(0xAAFFFFFF),
              fontSize: 12,
              fontFamily: 'monospace',
            ),
          ),
        
        const SizedBox(height: 24),
        
        // Progress percentage
        Text(
          '${(_purgeProgress * 100).toStringAsFixed(0)}%',
          style: const TextStyle(
            color: Color(0x80FFFFFF),
            fontSize: 14,
            fontFamily: 'monospace',
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
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

// ──────────────────────────────────────────────────────────────
// Mid-game Chat Overlay — Enter key opens a timed channel to ECHO
// ──────────────────────────────────────────────────────────────
class _ChatOverlay extends StatefulWidget {
  final EchoGame game;
  const _ChatOverlay({required this.game});

  @override
  State<_ChatOverlay> createState() => _ChatOverlayState();
}

class _ChatMessage {
  final String text;
  final bool fromPlayer;
  _ChatMessage(this.text, {required this.fromPlayer});
}

class _ChatOverlayState extends State<_ChatOverlay> {
  static const int _totalSeconds = 30;

  final TextEditingController _inputCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  final FocusNode _focusNode = FocusNode();

  final List<_ChatMessage> _messages = [];
  int _secondsLeft = _totalSeconds;
  bool _waiting = false;
  bool _closing = false;
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    // Greeting from ECHO
    _messages.add(_ChatMessage(
      _echoGreeting(),
      fromPlayer: false,
    ));
    _startCountdown();
    // Focus the input after frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  String _echoGreeting() {
    final phase = widget.game.round.clamp(1, 12);
    if (phase <= 3) return 'You opened a channel. Curious. What do you want to say?';
    if (phase <= 6) return 'You want to talk now? I already know what you\'re going to ask.';
    if (phase <= 9) return 'A conversation. How predictable. You have ${_totalSeconds}s.';
    return 'Stalling won\'t help. Say what you came to say.';
  }

  void _startCountdown() {
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) { timer.cancel(); return; }
      setState(() => _secondsLeft--);
      if (_secondsLeft <= 0) {
        timer.cancel();
        _timeUp();
      }
    });
  }

  void _timeUp() {
    if (_closing) return;
    setState(() {
      _closing = true;
      _messages.add(_ChatMessage(
        'Time\'s up. Back to the hunt.',
        fromPlayer: false,
      ));
    });
    _scrollToBottom();
    Future.delayed(const Duration(milliseconds: 1400), () {
      if (mounted) widget.game.closeChat();
    });
  }

  Future<void> _sendMessage() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty || _waiting || _closing) return;

    setState(() {
      _messages.add(_ChatMessage(text, fromPlayer: true));
      _waiting = true;
    });
    _inputCtrl.clear();
    _scrollToBottom();

    final reply = await widget.game.ai.chat(text, round: widget.game.round);

    if (!mounted) return;
    setState(() {
      _messages.add(_ChatMessage(reply, fromPlayer: false));
      _waiting = false;
    });
    _scrollToBottom();
    _focusNode.requestFocus();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress = _secondsLeft / _totalSeconds;
    final urgentColor = _secondsLeft <= 8
        ? const Color(0xFFFF1744)
        : const Color(0xFF00E5FF);

    return KeyboardListener(
      focusNode: FocusNode(),
      onKeyEvent: (event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          if (!_closing) widget.game.closeChat();
        }
      },
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 600, maxHeight: 520),
          margin: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
          decoration: BoxDecoration(
            color: const Color(0xF0060810),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: urgentColor.withAlpha(100),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: urgentColor.withAlpha(40),
                blurRadius: 40,
                spreadRadius: 8,
              ),
            ],
          ),
          child: Column(
            children: [
              // ── Header ──────────────────────────────────────────────
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: BoxDecoration(
                  color: urgentColor.withAlpha(18),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(9)),
                  border: Border(
                    bottom: BorderSide(color: urgentColor.withAlpha(60), width: 1),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.terminal, color: urgentColor, size: 14),
                    const SizedBox(width: 8),
                    Text(
                      'OPEN CHANNEL  ·  ECHO',
                      style: TextStyle(
                        color: urgentColor,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 3,
                        fontFamily: 'monospace',
                      ),
                    ),
                    const Spacer(),
                    // Countdown
                    Text(
                      '$_secondsLeft s',
                      style: TextStyle(
                        color: urgentColor,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'monospace',
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Escape hint
                    Text(
                      '[ESC]',
                      style: TextStyle(
                        color: urgentColor.withAlpha(80),
                        fontSize: 10,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),

              // ── Timer bar ───────────────────────────────────────────
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                height: 2,
                alignment: Alignment.centerLeft,
                color: Colors.transparent,
                child: FractionallySizedBox(
                  widthFactor: progress.clamp(0.0, 1.0),
                  child: Container(color: urgentColor.withAlpha(180)),
                ),
              ),

              // ── Message list ─────────────────────────────────────────
              Expanded(
                child: ListView.builder(
                  controller: _scrollCtrl,
                  padding: const EdgeInsets.all(16),
                  itemCount: _messages.length + (_waiting ? 1 : 0),
                  itemBuilder: (ctx, i) {
                    if (_waiting && i == _messages.length) {
                      return _buildTyping();
                    }
                    final msg = _messages[i];
                    return _buildBubble(msg);
                  },
                ),
              ),

              // ── Input ───────────────────────────────────────────────
              Container(
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(color: urgentColor.withAlpha(50), width: 1),
                  ),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    Text(
                      '> ',
                      style: TextStyle(
                        color: const Color(0xFF00E5FF).withAlpha(180),
                        fontFamily: 'monospace',
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Expanded(
                      child: TextField(
                        controller: _inputCtrl,
                        focusNode: _focusNode,
                        enabled: !_closing,
                        autofocus: true,
                        style: const TextStyle(
                          color: Color(0xFFE0F7FA),
                          fontFamily: 'monospace',
                          fontSize: 14,
                        ),
                        decoration: InputDecoration(
                          border: InputBorder.none,
                          hintText: _closing
                              ? 'Channel closing...'
                              : 'Speak to ECHO...',
                          hintStyle: TextStyle(
                            color: const Color(0xFF00E5FF).withAlpha(50),
                            fontFamily: 'monospace',
                            fontSize: 13,
                          ),
                        ),
                        onSubmitted: (_) => _sendMessage(),
                        maxLines: 1,
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.send, color: urgentColor.withAlpha(180), size: 18),
                      onPressed: _closing ? null : _sendMessage,
                      splashRadius: 18,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBubble(_ChatMessage msg) {
    final isEcho = !msg.fromPlayer;
    return Padding(
      padding: EdgeInsets.only(
        top: 6,
        bottom: 6,
        left: isEcho ? 0 : 48,
        right: isEcho ? 48 : 0,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isEcho) ...[
            Text(
              'ECHO  ',
              style: const TextStyle(
                color: Color(0xFFFF1744),
                fontFamily: 'monospace',
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
            ),
          ],
          Expanded(
            child: Text(
              msg.text,
              style: TextStyle(
                color: isEcho
                    ? const Color(0xFFFF6B6B)
                    : const Color(0xFF00E5FF),
                fontFamily: 'monospace',
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ),
          if (!isEcho) ...[
            const SizedBox(width: 8),
            const Text(
              'YOU',
              style: TextStyle(
                color: Color(0xFF00E5FF),
                fontFamily: 'monospace',
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTyping() {
    return const Padding(
      padding: EdgeInsets.only(top: 6, bottom: 6),
      child: Text(
        'ECHO  ...',
        style: TextStyle(
          color: Color(0x90FF1744),
          fontFamily: 'monospace',
          fontSize: 13,
          fontStyle: FontStyle.italic,
        ),
      ),
    );
  }
}
