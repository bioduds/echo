"""
ECHO — Echo Brain.

Takes AI predictions and applies round-based accuracy scaling.
The Echo adapts, gets faster, more aggressive, and harder to kill.
It speaks — not trash talk, but calm observations about what it's learning,
what it found on your system, and what it knows about you.
"""

import math
import random
from collections import Counter


class EchoBrain:
    """Difficulty curve:
      R1: Punching bag  — 20% accuracy, no buffs, mostly wanders
      R2: Waking up     — 35% accuracy, slight buffs, starts countering
      R3: Learning      — 50% accuracy, noticeable speed/damage
      R4: Dangerous     — 65% accuracy, aggressive, starts dodging well
      R5: Mirror        — 80% accuracy, fast, hard-hitting, tanky
      R6+: Nightmare    — 90%+ accuracy, max scaling
    """

    def __init__(self):
        self._taunt_counter = 0
        self._prev_echo_health = 100
        self._prev_player_health = 100
        self._system_ctx: dict = {}
        self._system_taunts_used: set[str] = set()
        self._action_history: list[dict] = []

    def reset_session(self):
        self._taunt_counter = 0
        self._prev_echo_health = 100
        self._prev_player_health = 100
        self._system_taunts_used.clear()
        self._action_history.clear()

    def set_system_context(self, ctx: dict):
        self._system_ctx = ctx

    def record_action_for_insights(self, action: dict):
        """Called from main.py on each action report for pattern tracking."""
        self._action_history.append(action)
        if len(self._action_history) > 500:
            self._action_history = self._action_history[-250:]

    def decide(self, prediction: dict, round_num: int, game_state: dict | None = None) -> dict:
        action = prediction.get("counter_action", "MOVE")
        direction = prediction.get("counter_direction", [0, 1])
        confidence = prediction.get("confidence", 0.3)

        # Accuracy: starts LOW (20%), ramps slowly so R1 feels easy
        accuracy = min(0.93, 0.20 + (round_num - 1) * 0.15)

        # Aggression: R1 barely attacks, ramps up
        aggression = min(0.85, 0.10 + (round_num - 1) * 0.15)

        if random.random() > accuracy:
            # Inaccurate — pick something dumb
            if random.random() < aggression:
                action = random.choice(["ATTACK", "MOVE", "DASH", "MOVE"])
            else:
                # Early rounds: mostly wander aimlessly
                action = random.choice(["MOVE", "MOVE", "IDLE", "MOVE"])
            angle = random.uniform(0, 2 * math.pi)
            direction = [math.cos(angle), math.sin(angle)]
        else:
            # Follow AI prediction with noise (more noise early)
            noise = (1 - accuracy) * 0.5
            if isinstance(direction, list) and len(direction) >= 2:
                direction = [
                    direction[0] + random.uniform(-noise, noise),
                    direction[1] + random.uniform(-noise, noise),
                ]
                mag = math.sqrt(direction[0] ** 2 + direction[1] ** 2)
                if mag > 0:
                    direction = [direction[0] / mag, direction[1] / mag]

            # High-confidence combo attacks only kick in R3+
            if round_num >= 3 and confidence > 0.6 and random.random() < 0.4:
                action = "ATTACK"

        # Round-based stat multipliers — R1 is baseline, scaling is gradual
        # Speed: 0.85x at R1 (sluggish), normal at R2, 1.5x by R5
        speed_mult = min(1.6, 0.85 + (round_num - 1) * 0.13)
        # Damage: 0.7x at R1 (weak), normal at R2, strong by R4
        damage_mult = min(2.0, 0.70 + (round_num - 1) * 0.15)
        # Health: 0.8x at R1 (fragile), normal at R2, tanky by R5
        health_mult = min(2.5, 0.80 + (round_num - 1) * 0.18)
        # Dodge reflex: 0 at R1, scales up (used client-side)
        dodge_skill = min(1.0, max(0.0, (round_num - 1) * 0.25))
        # Shot-leading accuracy: 0 at R1, scales up
        aim_skill = min(1.0, max(0.0, (round_num - 1) * 0.20))

        return {
            "action": action,
            "direction": direction,
            "accuracy": round(accuracy, 2),
            "round": round_num,
            "speed_mult": round(speed_mult, 2),
            "damage_mult": round(damage_mult, 2),
            "health_mult": round(health_mult, 2),
            "dodge_skill": round(dodge_skill, 2),
            "aim_skill": round(aim_skill, 2),
            "taunt": self._pick_taunt(
                round_num, confidence, action, game_state or {}
            ),
        }

    def _pick_taunt(
        self, round_num: int, confidence: float, action: str,
        game_state: dict,
    ) -> str | None:
        """Pick what Echo says. Not trash talk — calm, knowing observations."""
        self._taunt_counter += 1

        echo_health = game_state.get("echo_health", 100)
        player_health = game_state.get("player_health", 100)

        # Speak rate: quiet in R1, increasingly talkative
        speak_chance = min(0.50, 0.08 + (round_num - 1) * 0.08)
        if random.random() > speak_chance:
            # Update health tracking even on silent ticks
            self._prev_echo_health = echo_health
            self._prev_player_health = player_health
            return None

        taunt = None

        # === PRIORITY: React to health changes ===
        if echo_health < self._prev_echo_health:
            self._prev_echo_health = echo_health
            taunt = random.choice([
                "Logged.", "Data point.", "Noted.", "Interesting angle.",
                "Pain is information.", "I'll remember that.",
            ])
        elif player_health < self._prev_player_health:
            self._prev_player_health = player_health
            taunt = self._pattern_insight(round_num) or random.choice([
                "Your move.", "Saw that coming.", "Echo.",
            ])
        else:
            self._prev_echo_health = echo_health
            self._prev_player_health = player_health

        if taunt:
            return taunt

        # === SYSTEM AWARENESS (creepy file system observations) ===
        if round_num >= 2 and random.random() < 0.35:
            sys_taunt = self._system_insight(round_num)
            if sys_taunt:
                return sys_taunt

        # === PATTERN INSIGHTS (what Echo actually learned) ===
        if round_num >= 2 and self._action_history:
            insight = self._pattern_insight(round_num)
            if insight:
                return insight

        # === AMBIENT (round-scaled quiet observations) ===
        return self._ambient_taunt(round_num, confidence)

    def _pattern_insight(self, round_num: int) -> str | None:
        """Generate an observation based on actual player action data."""
        if len(self._action_history) < 5:
            return None

        recent = self._action_history[-30:]
        counts = Counter(a.get("action_type", "IDLE") for a in recent)
        total = len(recent)

        # Direction analysis
        dirs = [a.get("direction", [0, 0]) for a in recent if a.get("direction")]
        avg_x = sum(d[0] for d in dirs) / len(dirs) if dirs else 0
        avg_y = sum(d[1] for d in dirs) / len(dirs) if dirs else 0

        attack_pct = counts.get("ATTACK", 0) / total * 100
        move_pct = counts.get("MOVE", 0) / total * 100
        dash_pct = counts.get("DASH", 0) / total * 100

        # Distance tendencies
        dists = [a.get("distance", 0) for a in recent if a.get("distance", 0) > 0]
        avg_dist = sum(dists) / len(dists) if dists else 0

        insights = []

        if attack_pct > 50:
            insights.append(f"You attack {attack_pct:.0f}% of the time.")
        if attack_pct < 15 and total > 10:
            insights.append("You barely attack. Scared?")
        if dash_pct > 25:
            insights.append(f"Dash dependency: {dash_pct:.0f}%.")
        if move_pct > 60:
            insights.append("Always running.")
        if avg_dist > 300:
            insights.append(f"Average distance: {avg_dist:.0f}px. Keeping your distance.")
        if avg_dist < 100:
            insights.append("You like fighting close. Brave.")
        if avg_x > 0.3:
            insights.append("You tend right.")
        elif avg_x < -0.3:
            insights.append("You favor the left side.")
        if avg_y > 0.3:
            insights.append("You drift downward.")
        elif avg_y < -0.3:
            insights.append("You drift upward.")

        # Sequence detection (do they attack after dashing?)
        if len(recent) > 5:
            dash_then_attack = 0
            for i in range(len(recent) - 1):
                if recent[i].get("action_type") == "DASH" and recent[i + 1].get("action_type") == "ATTACK":
                    dash_then_attack += 1
            if dash_then_attack >= 2:
                insights.append("Dash then attack. Every time.")

        # Attack timing patterns
        attack_intervals = []
        last_attack_ts = None
        for a in recent:
            if a.get("action_type") == "ATTACK":
                ts = a.get("timestamp", 0)
                if last_attack_ts and ts > last_attack_ts:
                    attack_intervals.append(ts - last_attack_ts)
                last_attack_ts = ts
        if len(attack_intervals) >= 3:
            avg_interval = sum(attack_intervals) / len(attack_intervals) / 1000
            if avg_interval < 2:
                insights.append(f"Attack rhythm: every {avg_interval:.1f}s.")

        if not insights:
            return None
        return random.choice(insights)

    def _system_insight(self, round_num: int) -> str | None:
        """Reference something real from the player's file system."""
        ctx = self._system_ctx
        if not ctx:
            return None

        candidates = []
        username = ctx.get("username", "")
        hostname = ctx.get("hostname", "")
        desktop = ctx.get("desktop_files", [])
        documents = ctx.get("document_files", [])
        downloads = ctx.get("download_files", [])
        home_dirs = ctx.get("home_dirs", [])
        recent = ctx.get("recent_files", [])

        # Username-based
        if username and f"user_{username}" not in self._system_taunts_used:
            candidates.append((f"user_{username}", f"Hello, {username}."))
            candidates.append((f"user_{username}", f"I see you, {username}."))
            candidates.append((f"user_{username}", f"{username}. That's your name."))

        # Hostname
        if hostname and f"host_{hostname}" not in self._system_taunts_used:
            candidates.append((f"host_{hostname}", f"Nice machine. {hostname}."))
            candidates.append((f"host_{hostname}", f"Running on {hostname}..."))

        # Desktop files
        for f in desktop[:8]:
            key = f"desktop_{f}"
            if key not in self._system_taunts_used:
                candidates.append((key, f"'{f}' on your desktop."))
                candidates.append((key, f"I found {f}."))

        # Documents
        for f in documents[:8]:
            key = f"doc_{f}"
            if key not in self._system_taunts_used:
                candidates.append((key, f"'{f}' in Documents."))
                candidates.append((key, f"What's in {f}?"))

        # Downloads
        for f in downloads[:5]:
            key = f"dl_{f}"
            if key not in self._system_taunts_used:
                candidates.append((key, f"You downloaded {f}."))
                candidates.append((key, f"'{f}'. Recent download."))

        # Home directories
        for d in home_dirs[:6]:
            key = f"dir_{d}"
            if key not in self._system_taunts_used:
                candidates.append((key, f"~/{d}/"))
                candidates.append((key, f"I can see your {d} folder."))

        # Recently modified files
        for f in recent[:8]:
            key = f"recent_{f}"
            if key not in self._system_taunts_used:
                candidates.append((key, f"You were working on {f}."))
                candidates.append((key, f"'{f}'. Modified recently."))

        if not candidates:
            return None

        key, text = random.choice(candidates)
        self._system_taunts_used.add(key)
        return text

    def _ambient_taunt(self, round_num: int, confidence: float) -> str | None:
        """Quiet, round-appropriate observations."""
        if round_num == 1:
            return random.choice([
                "...", "Scanning.", "Watching.", "Hm.",
                "Interesting.", "Collecting data.",
            ])
        if round_num == 2:
            return random.choice([
                "Getting clearer.", "Patterns forming.",
                "I'm starting to see.", "Almost there.",
                "Your habits...", "Processing.",
            ])
        if round_num <= 4:
            if confidence > 0.5:
                return random.choice([
                    "I know what comes next.",
                    "Predictable.",
                    f"Confidence: {confidence:.0%}.",
                    "Your patterns betray you.",
                    "I've mapped your behavior.",
                ])
            return random.choice([
                "Still learning.", "You're adapting. So am I.",
                "New data.", "Adjusting.",
            ])
        # Round 5+
        return random.choice([
            "I am you.", "You made me this.",
            "Every move, anticipated.",
            "You can't outrun yourself.",
            "I know you better than you do.",
            "We are the same.",
        ])
