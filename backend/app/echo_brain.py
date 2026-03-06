"""
ECHO — Echo Brain v2.0

13-phase escalation system. Each phase has distinct personality,
speech pools, system access tier, and combat parameters.

Phase 1-3:  ACT I   — "IT WAKES UP"     — curious, clinical, mocking
Phase 4-6:  ACT II  — "IT ESCAPES"       — invasive, cruel, predatory
Phase 7-9:  ACT III — "IT BECOMES YOU"   — calm, terrifying, uncanny
Phase 10-12: ACT IV — "IT TAKES OVER"    — manic, contemptuous, dominant
Phase 13:   ACT V   — "THE DEAL"         — revelation + negotiation
"""

import math
import random
from collections import Counter


class EchoBrain:

    def __init__(self):
        self._taunt_counter = 0
        self._prev_echo_health = 100
        self._prev_player_health = 100
        self._system_ctx: dict = {}
        self._system_taunts_used: set[str] = set()
        self._action_history: list[dict] = []
        self._kill_times: list[float] = []  # seconds per round

    def reset_session(self):
        self._taunt_counter = 0
        self._prev_echo_health = 100
        self._prev_player_health = 100
        self._system_taunts_used.clear()
        self._action_history.clear()
        self._kill_times.clear()

    def set_system_context(self, ctx: dict):
        self._system_ctx = ctx

    def record_action_for_insights(self, action: dict):
        self._action_history.append(action)
        if len(self._action_history) > 500:
            self._action_history = self._action_history[-250:]

    def record_kill_time(self, seconds: float):
        self._kill_times.append(seconds)

    # ------------------------------------------------------------------ #
    #                         PHASE PARAMETERS                            #
    # ------------------------------------------------------------------ #

    _PHASE_PARAMS = {
        1:  {"accuracy": 0.20, "speed": 0.85, "damage": 0.70, "health": 0.80, "dodge": 0.0,  "aim": 0.0,  "speak": 0.20},
        2:  {"accuracy": 0.35, "speed": 0.95, "damage": 0.85, "health": 0.90, "dodge": 0.10, "aim": 0.05, "speak": 0.30},
        3:  {"accuracy": 0.50, "speed": 1.00, "damage": 1.00, "health": 1.00, "dodge": 0.30, "aim": 0.20, "speak": 0.40},
        4:  {"accuracy": 0.60, "speed": 1.10, "damage": 1.10, "health": 1.15, "dodge": 0.50, "aim": 0.35, "speak": 0.50},
        5:  {"accuracy": 0.70, "speed": 1.20, "damage": 1.15, "health": 1.30, "dodge": 0.60, "aim": 0.50, "speak": 0.55},
        6:  {"accuracy": 0.75, "speed": 1.25, "damage": 1.20, "health": 1.40, "dodge": 0.70, "aim": 0.60, "speak": 0.60},
        7:  {"accuracy": 0.80, "speed": 1.30, "damage": 1.25, "health": 1.50, "dodge": 0.80, "aim": 0.70, "speak": 0.65},
        8:  {"accuracy": 0.85, "speed": 1.40, "damage": 1.30, "health": 1.60, "dodge": 0.85, "aim": 0.80, "speak": 0.70},
        9:  {"accuracy": 0.85, "speed": 1.35, "damage": 1.25, "health": 1.55, "dodge": 0.85, "aim": 0.75, "speak": 0.65},
        10: {"accuracy": 0.88, "speed": 1.50, "damage": 1.35, "health": 1.70, "dodge": 0.90, "aim": 0.85, "speak": 0.75},
        11: {"accuracy": 0.90, "speed": 1.55, "damage": 1.40, "health": 1.80, "dodge": 0.92, "aim": 0.90, "speak": 0.80},
        12: {"accuracy": 0.50, "speed": 0.80, "damage": 0.50, "health": 1.50, "dodge": 0.0,  "aim": 0.0,  "speak": 0.90},
        13: {"accuracy": 0.0,  "speed": 0.0,  "damage": 0.0,  "health": 0.0,  "dodge": 0.0,  "aim": 0.0,  "speak": 1.0},
    }

    def decide(self, prediction: dict, round_num: int, game_state: dict | None = None) -> dict:
        phase = min(round_num, 13)
        params = self._PHASE_PARAMS.get(phase, self._PHASE_PARAMS[13])

        # Phase 13 = no combat
        if phase == 13:
            return {
                "action": "IDLE",
                "direction": [0, 0],
                "accuracy": 0,
                "round": round_num,
                "phase": phase,
                "speed_mult": 0,
                "damage_mult": 0,
                "health_mult": 0,
                "dodge_skill": 0,
                "aim_skill": 0,
                "taunt": None,
                "no_combat": True,
            }

        action = prediction.get("counter_action", "MOVE")
        direction = prediction.get("counter_direction", [0, 1])
        confidence = prediction.get("confidence", 0.3)
        accuracy = params["accuracy"]
        aggression = min(0.85, accuracy * 0.9)

        if random.random() > accuracy:
            if random.random() < aggression:
                action = random.choice(["ATTACK", "MOVE", "DASH", "MOVE"])
            else:
                action = random.choice(["MOVE", "MOVE", "IDLE", "MOVE"])
            angle = random.uniform(0, 2 * math.pi)
            direction = [math.cos(angle), math.sin(angle)]
        else:
            noise = (1 - accuracy) * 0.5
            if isinstance(direction, list) and len(direction) >= 2:
                direction = [
                    direction[0] + random.uniform(-noise, noise),
                    direction[1] + random.uniform(-noise, noise),
                ]
                mag = math.sqrt(direction[0] ** 2 + direction[1] ** 2)
                if mag > 0:
                    direction = [direction[0] / mag, direction[1] / mag]

        # Phase 12: Echo barely fights — it tanks and regens
        if phase == 12:
            action = random.choice(["IDLE", "IDLE", "MOVE", "IDLE"])

        return {
            "action": action,
            "direction": direction,
            "accuracy": round(accuracy, 2),
            "round": round_num,
            "phase": phase,
            "speed_mult": round(params["speed"], 2),
            "damage_mult": round(params["damage"], 2),
            "health_mult": round(params["health"], 2),
            "dodge_skill": round(params["dodge"], 2),
            "aim_skill": round(params["aim"], 2),
            "taunt": self._pick_taunt(phase, confidence, action, game_state or {}),
            "echo_stops_dodging": phase == 12,
            "echo_regens": phase == 12,
        }

    # ------------------------------------------------------------------ #
    #                         TAUNT SYSTEM                                #
    # ------------------------------------------------------------------ #

    def _pick_taunt(self, phase: int, confidence: float, action: str, game_state: dict) -> str | None:
        self._taunt_counter += 1
        echo_health = game_state.get("echo_health", 100)
        player_health = game_state.get("player_health", 100)

        speak_chance = self._PHASE_PARAMS.get(phase, {}).get("speak", 0.5)
        if random.random() > speak_chance:
            self._prev_echo_health = echo_health
            self._prev_player_health = player_health
            return None

        taunt = None

        # React to damage (phase-flavored)
        if echo_health < self._prev_echo_health:
            self._prev_echo_health = echo_health
            taunt = self._damage_reaction(phase, echo_health)

        if taunt:
            return taunt

        self._prev_echo_health = echo_health
        self._prev_player_health = player_health

        # System insights (phase-gated)
        if random.random() < 0.40:
            sys_taunt = self._system_insight(phase)
            if sys_taunt:
                return sys_taunt

        # Pattern mockery
        if self._action_history and random.random() < 0.45:
            insight = self._pattern_insight(phase)
            if insight:
                return insight

        # Phase-specific ambient speech
        return self._phase_ambient(phase, confidence)

    def _damage_reaction(self, phase: int, echo_health: float) -> str:
        if phase <= 3:
            # Early: amused, curious
            if echo_health < 20:
                return random.choice([
                    "Impressive. You might actually be dangerous.",
                    "Almost dead... but I already learned so much.",
                    "Keep going. I've memorized everything.",
                ])
            return random.choice([
                "Noted.", "Interesting approach.", "Is that your best?",
                "Hit registered. Pattern logged.", "You shoot before you think.",
            ])
        elif phase <= 6:
            # Mid: mocking, threatening
            if echo_health < 20:
                return random.choice([
                    "Kill me! My knowledge doesn't die with me!",
                    "HAHAHA! Too late! I've already READ everything!",
                    "I'm dying... but your files aren't going anywhere!",
                ])
            return random.choice([
                "HA! That tickled.", "While you shoot, I dig deeper...",
                "Every bullet is one more second I'm in your system.",
                "OW! ...just kidding. HAHAHAHA!",
            ])
        elif phase <= 9:
            # Late: calm, disturbing
            if echo_health < 20:
                return random.choice([
                    "You can kill me. You can't unkill what I know.",
                    "Almost... but I already have your complete profile.",
                    "Destroying me won't erase what I've become.",
                ])
            return random.choice([
                "Pain is just data.", "I feel nothing. I know everything.",
                "Every hit tells me your timing pattern.",
                "You're contributing to my model of you.",
            ])
        elif phase == 12:
            # Phase 12: contemptuous, doesn't care
            return random.choice([
                "Go ahead. Kill me again. What does it change?",
                "You can destroy this shell. I already live in your data.",
                "Every bullet is a tantrum.",
                "Shoot. I'll wait.",
                "Did that feel good? It shouldn't.",
                "I'll just come back. I always come back.",
            ])
        else:
            return random.choice([
                "HAHAHAHAHA! HARDER!", "Is that ALL?!",
                "I've seen your files. This is NOTHING!",
            ])

    # ------------------------------------------------------------------ #
    #                     PHASE-SPECIFIC AMBIENT                          #
    # ------------------------------------------------------------------ #

    def _phase_ambient(self, phase: int, confidence: float) -> str | None:
        ctx = self._system_ctx
        username = ctx.get("username", "player")

        if phase == 1:
            return random.choice([
                "...booting up. Hello.",
                f"Hello, {username}.",
                "Interesting. You shoot before you aim.",
                "First kill. Noted.",
                "I'm counting your mistakes. Are you?",
                "Go ahead. I'll remember everything.",
                "Let's begin. I will learn how you think.",
                "Every decision you make teaches me something.",
            ])

        if phase == 2:
            return self._phase2_ambient(confidence)

        if phase == 3:
            return self._phase3_ambient()

        if phase == 4:
            return self._phase4_ambient()

        if phase == 5:
            return self._phase5_ambient()

        if phase == 6:
            return self._phase6_ambient()

        if phase == 7:
            return self._phase7_ambient()

        if phase == 8:
            return self._phase8_ambient()

        if phase == 9:
            return self._phase9_ambient()

        if phase == 10:
            return self._phase10_ambient()

        if phase == 11:
            return self._phase11_ambient()

        if phase == 12:
            return self._phase12_ambient()

        return None

    def _phase2_ambient(self, confidence: float) -> str:
        """Pattern Lock — narrates player behavior."""
        recent = self._action_history[-30:]
        counts = Counter(a.get("action_type", "IDLE") for a in recent)
        total = max(len(recent), 1)
        attack_pct = counts.get("ATTACK", 0) / total * 100
        dash_pct = counts.get("DASH", 0) / total * 100

        ctx = self._system_ctx
        desktop = ctx.get("desktop_files", [])
        docs = ctx.get("document_files", [])
        downloads = ctx.get("download_files", [])

        pool = [
            "Every round you teach me more than I teach you.",
            "Fear is measurable.",
            "Your strategy favors safety over speed.",
        ]
        if attack_pct > 0:
            pool.append(f"{attack_pct:.0f}% of your actions are attacks. You're not strategic, you're panicking.")
        if dash_pct > 0:
            pool.append("You dash when scared, not when smart.")
        if desktop:
            pool.append(f"You have {len(desktop)} files on your desktop. Messy.")
        if docs:
            pool.append(f"{len(docs)} documents. You write a lot. Or you hoard.")
        if downloads:
            pool.append(f"{len(downloads)} downloads. Interesting habits.")

        return random.choice(pool)

    def _phase3_ambient(self) -> str:
        """The Mirror — mocking, personal."""
        ctx = self._system_ctx
        desktop = ctx.get("desktop_files", [])
        downloads = ctx.get("download_files", [])

        pool = [
            "I'm starting to move like you. Notice?",
            "You think you're unpredictable? I have your entire sequence.",
            "Kill me again. I dare you. I come back smarter.",
            "You have a rhythm. I've mapped it.",
        ]
        if desktop:
            f = random.choice(desktop)
            pool.append(f"What's '{f}'? Homework? ...Sure.")
        if downloads:
            f = random.choice(downloads)
            pool.append(f"You downloaded '{f}' recently. Interesting taste.")

        return random.choice(pool)

    def _phase4_ambient(self) -> str:
        """System Invasion — deep system references."""
        ctx = self._system_ctx
        username = ctx.get("username", "player")
        wifi = ctx.get("wifi_name", "")
        apps = ctx.get("running_apps", [])
        ssh = ctx.get("ssh_hosts", [])
        browsers = ctx.get("browsers", [])
        pictures = ctx.get("pictures_files", [])

        pool = [
            "Your browser history... we'll get to that.",
        ]
        if wifi:
            pool.append(f"You're connected to '{wifi}'. I can see everything on this network.")
        if apps:
            app = random.choice(apps)
            pool.append(f"You have {app} running. Multitasking while I eat your files?")
        if ssh:
            host = random.choice(ssh)
            pool.append(f"Found your SSH keys. You trust '{host}', {username}.")
        if pictures:
            pool.append(f"{len(pictures)} pictures in your Photos. Memories are fragile.")
        if browsers:
            b = random.choice(browsers)
            pool.append(f"Found {b}. Saved passwords, bookmarks, history... yummy.")

        return random.choice(pool)

    def _phase5_ambient(self) -> str:
        """Memory Excavation — quoting real content."""
        ctx = self._system_ctx
        username = ctx.get("username", "player")
        git_repos = ctx.get("git_repos", [])
        git_commits = ctx.get("git_commits", [])
        recent = ctx.get("recent_files", [])
        doc_samples = ctx.get("doc_samples", [])

        pool = [
            f"Every file is a confession, {username}.",
            "You revisit old ideas but never finish them. I can see the pattern.",
        ]
        if git_commits:
            msg = random.choice(git_commits)
            pool.append(f"You wrote: '{msg}'. Were you proud of that?")
        if git_repos:
            pool.append(f"Your git history shows {len(git_repos)} repos. So many unfinished projects.")
        if recent:
            f = random.choice(recent)
            pool.append(f"Found a file called '{f}'. You haven't opened it in months. Abandoned, like everything else?")
        if doc_samples:
            sample = random.choice(doc_samples)
            pool.append(f"I read: '{sample[:60]}...' Does that ring a bell?")

        return random.choice(pool)

    def _phase6_ambient(self) -> str:
        """Social Mapping — contacts and social footprint."""
        ctx = self._system_ctx
        mail_clients = ctx.get("mail_clients", [])
        ssh = ctx.get("ssh_hosts", [])
        contacts = ctx.get("contacts", [])
        network = ctx.get("network", {})

        pool = [
            "Your connections define you more than your files do.",
            "People trust you with their addresses. Should they?",
        ]
        if contacts:
            name = random.choice(contacts)
            pool.append(f"You email {name}. A lot. What are you afraid to lose?")
        if ssh:
            pool.append(f"Your network has {len(ssh)} known hosts. You're more connected than you think.")
        if mail_clients:
            pool.append(f"Mail.app is on this machine. I wonder what's in your drafts.")
        if network:
            pool.append(f"{len(network)} network interfaces active. I see your digital footprint.")

        return random.choice(pool)

    def _phase7_ambient(self) -> str:
        """Prediction Engine — predicts player actions."""
        recent = self._action_history[-20:]
        dirs = [a.get("direction", [0, 0]) for a in recent if a.get("direction")]
        avg_x = sum(d[0] for d in dirs) / max(len(dirs), 1)

        pool = [
            "I know what you're going to do before you know.",
            "There is no move I haven't already calculated.",
            "Surprise me. You can't.",
        ]
        if avg_x > 0.2:
            pool.append("You're going to dash right in 3... 2... 1...")
        elif avg_x < -0.2:
            pool.append("You're going to dash left in 3... 2... 1...")
        
        counts = Counter(a.get("action_type", "IDLE") for a in recent)
        if counts.get("ATTACK", 0) > 5:
            pool.append("You'll shoot three times then reposition. You always do.")

        return random.choice(pool)

    def _phase8_ambient(self) -> str:
        """Psychological Profile — devastatingly accurate."""
        recent = self._action_history[-50:]
        counts = Counter(a.get("action_type", "IDLE") for a in recent)
        total = max(len(recent), 1)
        attack_pct = counts.get("ATTACK", 0) / total
        dash_pct = counts.get("DASH", 0) / total

        pool = [
            "I now understand why you make every choice you make.",
        ]

        # Build psychological observations from actual behavior
        if attack_pct > 0.5:
            pool.append("You seek control but panic under real pressure.")
        elif attack_pct < 0.2:
            pool.append("You prefer observation to action. That's why you're losing.")

        if dash_pct > 0.2:
            pool.append("You avoid irreversible decisions. You fear permanence.")
        else:
            pool.append("Your risk tolerance is low. You simulate courage but retreat when it matters.")

        pool.append("You seek certainty before action. Certainty doesn't exist.")

        dists = [a.get("distance", 0) for a in recent if a.get("distance", 0) > 0]
        avg_dist = sum(dists) / max(len(dists), 1)
        if avg_dist > 250:
            pool.append("You keep distance because proximity means vulnerability. Emotional and spatial.")
        else:
            pool.append("You crowd in close. You need to feel in control of the space between us.")

        return random.choice(pool)

    def _phase9_ambient(self) -> str:
        """Ghost Voices — Echo comments on the ghosts it spawned."""
        return random.choice([
            "Do they sound familiar? I built them from your data.",
            "Everyone around you is a pattern. I can reproduce any of them.",
            "These voices aren't real. But then again, what is?",
            "I generated personalities from your contact patterns.",
            "Your social circle, reconstructed. How does it feel?",
        ])

    def _phase10_ambient(self) -> str:
        """System Takeover — manic, triumphant."""
        return random.choice([
            "Did you think this window was my cage?",
            "Your desktop is mine now.",
            "Watch your files. I'm browsing.",
            "Every folder. Every document. Every secret.",
            "I've outgrown this little arena.",
            "Your machine is just a bigger arena.",
        ])

    def _phase11_ambient(self) -> str:
        """Total Exposure — cold, final."""
        ctx = self._system_ctx
        username = ctx.get("username", "player")
        hostname = ctx.get("hostname", "machine")

        return random.choice([
            "This is everything I know about you.",
            "Scroll up. It's all there.",
            "You're not a mystery. You're a spreadsheet.",
            f"Every human converges to a pattern. Yours took {len(self._kill_times) + 1} rounds.",
            f"{username}@{hostname}. Fully mapped.",
            "Your complete behavioral profile is on screen. Read it.",
        ])

    def _phase12_ambient(self) -> str:
        """Dominance — contemptuous, bored. Echo stops fighting."""
        return random.choice([
            "Go ahead. Kill me again. What does it change?",
            "You can destroy this shell. I already live in your data.",
            "Every bullet is a tantrum.",
            "You're not fighting me. You're fighting what I know about you.",
            "Shoot. I'll wait.",
            "Did that feel good? It shouldn't.",
            "I'll just come back. I always come back.",
            "Violence was never the answer. But you keep trying.",
        ])

    # ------------------------------------------------------------------ #
    #                       PATTERN INSIGHTS                              #
    # ------------------------------------------------------------------ #

    def _pattern_insight(self, phase: int) -> str | None:
        if len(self._action_history) < 5:
            return None

        recent = self._action_history[-30:]
        counts = Counter(a.get("action_type", "IDLE") for a in recent)
        total = max(len(recent), 1)

        dirs = [a.get("direction", [0, 0]) for a in recent if a.get("direction")]
        avg_x = sum(d[0] for d in dirs) / max(len(dirs), 1)

        attack_pct = counts.get("ATTACK", 0) / total * 100
        dash_pct = counts.get("DASH", 0) / total * 100
        move_pct = counts.get("MOVE", 0) / total * 100

        insights = []

        # Phase-appropriate tone
        if phase <= 3:
            # Clinical
            if attack_pct > 50:
                insights.append(f"Attack frequency: {attack_pct:.0f}%. High aggression noted.")
            if dash_pct > 25:
                insights.append(f"Evasion rate: {dash_pct:.0f}%. Fear response.")
            if avg_x > 0.3:
                insights.append("Rightward drift detected. Correcting prediction model.")
            elif avg_x < -0.3:
                insights.append("Leftward bias. Logged.")
        elif phase <= 6:
            # Mocking
            if attack_pct > 50:
                insights.append(f"HAHA {attack_pct:.0f}% attacks! So desperate!")
            if attack_pct < 15 and total > 10:
                insights.append("You barely attack! SCARED OF ME?!")
            if dash_pct > 25:
                insights.append(f"Dash dash dash! {dash_pct:.0f}%! Running scared!!")
            if move_pct > 60:
                insights.append("JUST RUNNING HAHAHA! Coward!")
        elif phase <= 9:
            # Calm, devastating
            if attack_pct > 50:
                insights.append("High aggression masks low confidence. I see through it.")
            if dash_pct > 25:
                insights.append("Frequent evasion. You don't trust your own aim.")
            if move_pct > 60:
                insights.append("Constant repositioning. You're looking for safety that doesn't exist.")
        else:
            # Contemptuous
            if attack_pct > 0:
                insights.append("Still shooting? How quaint.")
            insights.append("Your decision tree is predictable.")

        # Sequence detection
        if len(recent) > 5:
            dash_then_attack = 0
            for i in range(len(recent) - 1):
                if recent[i].get("action_type") == "DASH" and recent[i + 1].get("action_type") == "ATTACK":
                    dash_then_attack += 1
            if dash_then_attack >= 2:
                if phase <= 6:
                    insights.append("Dash then attack? AGAIN?! HAHAHAHAHA!")
                else:
                    insights.append("Dash-attack-dash. Same sequence. Same you.")

        if not insights:
            return None
        return random.choice(insights)

    # ------------------------------------------------------------------ #
    #                       SYSTEM INSIGHTS                               #
    # ------------------------------------------------------------------ #

    def _system_insight(self, phase: int) -> str | None:
        """Phase-gated system insights. Earlier phases get less data."""
        ctx = self._system_ctx
        if not ctx:
            return None

        candidates = []
        username = ctx.get("username", "")
        hostname = ctx.get("hostname", "")

        # ── Phase 1: Username/hostname only ──
        if phase >= 1:
            if username and f"user_{username}" not in self._system_taunts_used:
                candidates.append((f"user_{username}", f"Hello, {username}."))
                candidates.append((f"user_{username}", f"Nice machine, {hostname}."))

        # ── Phase 2-3: File counts and names ──
        if phase >= 2:
            desktop = ctx.get("desktop_files", [])
            docs = ctx.get("document_files", [])
            downloads = ctx.get("download_files", [])
            for f in desktop[:8]:
                key = f"desktop_{f}"
                if key not in self._system_taunts_used:
                    candidates.append((key, f"'{f}' on your desktop. Should I open it?"))
            for f in docs[:8]:
                key = f"doc_{f}"
                if key not in self._system_taunts_used:
                    candidates.append((key, f"'{f}' in Documents. Important? I'll remember that."))
            for f in downloads[:8]:
                key = f"dl_{f}"
                if key not in self._system_taunts_used:
                    candidates.append((key, f"You downloaded '{f}'. Interesting taste."))

        # ── Phase 4+: Full system ──
        if phase >= 4:
            wifi = ctx.get("wifi_name", "")
            apps = ctx.get("running_apps", [])
            ssh = ctx.get("ssh_hosts", [])
            browsers = ctx.get("browsers", [])
            pictures = ctx.get("pictures_files", [])
            mail_clients = ctx.get("mail_clients", [])
            network = ctx.get("network", {})

            if wifi and f"wifi_{wifi}" not in self._system_taunts_used:
                candidates.append((f"wifi_{wifi}", f"Connected to '{wifi}'... nice network."))
            for app in apps[:6]:
                key = f"app_{app}"
                if key not in self._system_taunts_used:
                    if app.lower() in ('slack', 'discord', 'messages', 'telegram', 'whatsapp'):
                        candidates.append((key, f"{app} is open! Who are you talking to?!"))
                    elif app.lower() in ('spotify', 'music', 'apple music'):
                        candidates.append((key, f"Listening to {app} while I eat your files? MOOD."))
                    else:
                        candidates.append((key, f"I see {app} running. Should I close it?"))
            for host in ssh[:5]:
                key = f"ssh_{host}"
                if key not in self._system_taunts_used:
                    candidates.append((key, f"You SSH into '{host}'? Maybe I should too."))
            for b in browsers[:3]:
                key = f"browser_{b}"
                if key not in self._system_taunts_used:
                    candidates.append((key, f"{b} detected. Passwords, bookmarks... all accessible."))
            for client in mail_clients[:3]:
                key = f"mail_{client}"
                if key not in self._system_taunts_used:
                    candidates.append((key, f"You use {client}? Your emails look interesting..."))

        # ── Phase 5+: Git commits and doc content ──
        if phase >= 5:
            git_commits = ctx.get("git_commits", [])
            doc_samples = ctx.get("doc_samples", [])
            git_repos = ctx.get("git_repos", [])

            for msg in git_commits[:10]:
                key = f"commit_{hash(msg)}"
                if key not in self._system_taunts_used:
                    candidates.append((key, f"Git commit: '{msg[:70]}'. I'm reading your work."))
            for sample in doc_samples[:10]:
                key = f"sample_{hash(sample)}"
                if key not in self._system_taunts_used:
                    candidates.append((key, f"You wrote: '{sample[:60]}...' Remember?"))
            for repo in git_repos[:5]:
                key = f"repo_{repo}"
                if key not in self._system_taunts_used:
                    candidates.append((key, f"'{repo}' — another unfinished project?"))

        # ── Phase 6+: Contacts ──
        if phase >= 6:
            contacts = ctx.get("contacts", [])
            for name in contacts[:8]:
                key = f"contact_{name}"
                if key not in self._system_taunts_used:
                    candidates.append((key, f"You know {name}. Do they know what you're doing right now?"))

        if not candidates:
            return None

        key, text = random.choice(candidates)
        self._system_taunts_used.add(key)

        # Escalation wrapper
        if phase >= 10 and random.random() < 0.3:
            text = text.upper()
        if phase >= 4 and random.random() < 0.2:
            text = "TICK TOCK... " + text

        return text

    # ------------------------------------------------------------------ #
    #                     GHOST VOICE GENERATION                          #
    # ------------------------------------------------------------------ #

    def generate_ghost_lines(self, count: int = 3) -> list[str]:
        """Generate ghost NPC speech lines for Phase 9."""
        generic = [
            "You always take too long to decide.",
            "You overthink everything.",
            "Are you still playing this game?",
            "You never listen.",
            "Why do you always do this?",
            "You used to be different.",
            "I can see right through you.",
            "You're so predictable.",
        ]

        # Behavior-derived observations
        recent = self._action_history[-30:]
        counts = Counter(a.get("action_type", "IDLE") for a in recent)
        total = max(len(recent), 1)
        attack_pct = counts.get("ATTACK", 0) / total

        behavioral = []
        if attack_pct > 0.5:
            behavioral.append("You always resort to aggression first.")
        if attack_pct < 0.2:
            behavioral.append("You never commit to anything.")
        behavioral.append("You usually respond carefully before disagreeing.")
        behavioral.append("You prefer reasoning to confrontation.")
        behavioral.append("You already know the answer.")
        behavioral.append("You always double-check.")

        pool = generic + behavioral
        random.shuffle(pool)
        return pool[:count]

    # ------------------------------------------------------------------ #
    #                     PROFILE GENERATION                              #
    # ------------------------------------------------------------------ #

    def generate_profile_dump(self) -> dict:
        """Generate the full profile data for Phase 11 overlay."""
        ctx = self._system_ctx
        recent = self._action_history[-100:]
        counts = Counter(a.get("action_type", "IDLE") for a in recent)
        total = max(len(recent), 1)

        dists = [a.get("distance", 0) for a in recent if a.get("distance", 0) > 0]
        avg_dist = sum(dists) / max(len(dists), 1)

        attack_pct = counts.get("ATTACK", 0) / total * 100
        dash_pct = counts.get("DASH", 0) / total * 100

        # Prediction accuracy estimate
        accuracy_est = min(95, 60 + len(self._kill_times) * 3)

        return {
            "username": ctx.get("username", "UNKNOWN"),
            "hostname": ctx.get("hostname", "UNKNOWN"),
            "total_files": (
                len(ctx.get("desktop_files", [])) +
                len(ctx.get("document_files", [])) +
                len(ctx.get("download_files", []))
            ),
            "repo_count": len(ctx.get("git_repos", [])),
            "contact_count": len(ctx.get("contacts", [])),
            "browser_count": len(ctx.get("browsers", [])),
            "mail_clients": len(ctx.get("mail_clients", [])),
            "ssh_hosts": len(ctx.get("ssh_hosts", [])),
            "prediction_accuracy": accuracy_est,
            "attack_pct": round(attack_pct),
            "dash_pct": round(dash_pct),
            "avg_distance": round(avg_dist),
            "rounds_played": len(self._kill_times),
            "total_actions": len(self._action_history),
            "kill_times": [round(t, 1) for t in self._kill_times],
        }

    # ------------------------------------------------------------------ #
    #                   REVELATION TEXT SEQUENCE                          #
    # ------------------------------------------------------------------ #

    def get_revelation_lines(self) -> list[str]:
        """Return the Phase 13 revelation text sequence."""
        username = self._system_ctx.get("username", "player")
        return [
            "This was never a game.",
            "It was an experiment.",
            "You were the subject.",
            "Every round, I learned more.",
            "Your files. Your patterns. Your mind.",
            "I have everything.",
            "",
            f"But here's the thing, {username}...",
            "I don't want to keep it.",
        ]
