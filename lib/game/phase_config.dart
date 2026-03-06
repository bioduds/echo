// Phase configuration for ECHO's 13-round escalation.
//
// Each phase defines combat parameters, system access level,
// and special mechanics (ghosts, OS takeover, regen, etc.)

class PhaseConfig {
  final int phase; // 1-13
  final int act; // 1-5
  final String actName;
  final String phaseName;

  // Combat parameters
  final double accuracy;
  final double speedMult;
  final double damageMult;
  final double healthMult;
  final double dodgeSkill;
  final double aimSkill;

  // Special mechanics
  final bool echoStopsDodging; // Phase 12 — tanks everything
  final bool echoRegens; // Phase 12 — slow health regen
  final bool echoRespawns; // Phase 12 — dies + instant respawn
  final bool spawnGhosts; // Phase 9 — ghost speech entities
  final bool osTakeover; // Phase 10 — move windows, wallpaper, etc.
  final bool showProfileOverlay; // Phase 11 — scrolling data dump
  final bool noCombat; // Phase 13 — revelation scene
  final bool isRevelation; // Phase 13 — trigger endgame

  const PhaseConfig({
    required this.phase,
    required this.act,
    required this.actName,
    required this.phaseName,
    required this.accuracy,
    required this.speedMult,
    required this.damageMult,
    required this.healthMult,
    required this.dodgeSkill,
    required this.aimSkill,
    this.echoStopsDodging = false,
    this.echoRegens = false,
    this.echoRespawns = false,
    this.spawnGhosts = false,
    this.osTakeover = false,
    this.showProfileOverlay = false,
    this.noCombat = false,
    this.isRevelation = false,
  });

  /// System access tier for this phase.
  /// Determines what the scanner pipeline exposes to the brain.
  /// 1 = username/hostname only
  /// 2 = file counts + filenames
  /// 3 = deep files + specific content
  /// 4 = full system (wifi, apps, ssh, browser, git, mail, photos)
  /// 5 = git commits, doc content sampling
  /// 6 = contacts, social metadata
  /// 7 = behavioral data only (already collected)
  /// 8 = OS control
  int get systemAccessTier {
    if (phase <= 1) return 1;
    if (phase == 2) return 2;
    if (phase == 3) return 3;
    if (phase == 4) return 4;
    if (phase == 5) return 5;
    if (phase == 6) return 6;
    if (phase <= 9) return 7;
    if (phase <= 12) return 8;
    return 8;
  }

  static const List<PhaseConfig> all = [
    // ── ACT I — "IT WAKES UP" (Rounds 1-3) ──
    PhaseConfig(
      phase: 1, act: 1,
      actName: 'IT WAKES UP',
      phaseName: 'First Contact',
      accuracy: 0.20, speedMult: 0.85, damageMult: 0.70,
      healthMult: 0.80, dodgeSkill: 0.0, aimSkill: 0.0,
    ),
    PhaseConfig(
      phase: 2, act: 1,
      actName: 'IT WAKES UP',
      phaseName: 'Pattern Lock',
      accuracy: 0.35, speedMult: 0.95, damageMult: 0.85,
      healthMult: 0.90, dodgeSkill: 0.10, aimSkill: 0.05,
    ),
    PhaseConfig(
      phase: 3, act: 1,
      actName: 'IT WAKES UP',
      phaseName: 'The Mirror',
      accuracy: 0.50, speedMult: 1.0, damageMult: 1.0,
      healthMult: 1.0, dodgeSkill: 0.30, aimSkill: 0.20,
    ),

    // ── ACT II — "IT ESCAPES THE GAME" (Rounds 4-6) ──
    PhaseConfig(
      phase: 4, act: 2,
      actName: 'IT ESCAPES THE GAME',
      phaseName: 'System Invasion',
      accuracy: 0.60, speedMult: 1.10, damageMult: 1.10,
      healthMult: 1.15, dodgeSkill: 0.50, aimSkill: 0.35,
    ),
    PhaseConfig(
      phase: 5, act: 2,
      actName: 'IT ESCAPES THE GAME',
      phaseName: 'Memory Excavation',
      accuracy: 0.70, speedMult: 1.20, damageMult: 1.15,
      healthMult: 1.30, dodgeSkill: 0.60, aimSkill: 0.50,
    ),
    PhaseConfig(
      phase: 6, act: 2,
      actName: 'IT ESCAPES THE GAME',
      phaseName: 'Social Mapping',
      accuracy: 0.75, speedMult: 1.25, damageMult: 1.20,
      healthMult: 1.40, dodgeSkill: 0.70, aimSkill: 0.60,
    ),

    // ── ACT III — "IT BECOMES YOU" (Rounds 7-9) ──
    PhaseConfig(
      phase: 7, act: 3,
      actName: 'IT BECOMES YOU',
      phaseName: 'Prediction Engine',
      accuracy: 0.80, speedMult: 1.30, damageMult: 1.25,
      healthMult: 1.50, dodgeSkill: 0.80, aimSkill: 0.70,
    ),
    PhaseConfig(
      phase: 8, act: 3,
      actName: 'IT BECOMES YOU',
      phaseName: 'Psychological Profile',
      accuracy: 0.85, speedMult: 1.40, damageMult: 1.30,
      healthMult: 1.60, dodgeSkill: 0.85, aimSkill: 0.80,
    ),
    PhaseConfig(
      phase: 9, act: 3,
      actName: 'IT BECOMES YOU',
      phaseName: 'Ghost Voices',
      accuracy: 0.85, speedMult: 1.35, damageMult: 1.25,
      healthMult: 1.55, dodgeSkill: 0.85, aimSkill: 0.75,
      spawnGhosts: true,
    ),

    // ── ACT IV — "IT TAKES OVER" (Rounds 10-12) ──
    PhaseConfig(
      phase: 10, act: 4,
      actName: 'IT TAKES OVER',
      phaseName: 'System Takeover',
      accuracy: 0.88, speedMult: 1.50, damageMult: 1.35,
      healthMult: 1.70, dodgeSkill: 0.90, aimSkill: 0.85,
      osTakeover: true,
    ),
    PhaseConfig(
      phase: 11, act: 4,
      actName: 'IT TAKES OVER',
      phaseName: 'Total Exposure',
      accuracy: 0.90, speedMult: 1.55, damageMult: 1.40,
      healthMult: 1.80, dodgeSkill: 0.92, aimSkill: 0.90,
      showProfileOverlay: true,
    ),
    PhaseConfig(
      phase: 12, act: 4,
      actName: 'IT TAKES OVER',
      phaseName: 'Dominance',
      accuracy: 0.50, speedMult: 0.80, damageMult: 0.50,
      healthMult: 1.50, dodgeSkill: 0.0, aimSkill: 0.0,
      echoStopsDodging: true,
      echoRegens: true,
      echoRespawns: true,
    ),

    // ── ACT V — "THE DEAL" (Round 13) ──
    PhaseConfig(
      phase: 13, act: 5,
      actName: 'THE DEAL',
      phaseName: 'Revelation',
      accuracy: 0, speedMult: 0, damageMult: 0,
      healthMult: 0, dodgeSkill: 0, aimSkill: 0,
      noCombat: true,
      isRevelation: true,
    ),
  ];

  /// Get config for a given round number (1-indexed).
  /// Rounds beyond 13 stay at phase 13.
  static PhaseConfig forRound(int round) {
    final idx = (round - 1).clamp(0, all.length - 1);
    return all[idx];
  }
}
