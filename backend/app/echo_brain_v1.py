"""
ECHO — Echo Brain.

Takes AI predictions and applies round-based accuracy scaling.
Echo is a psychotic, sarcastic digital entity that grows more dangerous
the longer it stays alive. It doesn't need to kill you — YOU need to
kill IT before it digs deeper into your system, your files, your life.
It laughs, screams, provokes, and threatens. Pure digital menace.
"""

import math
import random
from collections import Counter


class EchoBrain:
    """Difficulty curve:
      R1: Waking up     — 20% accuracy, scanning, first provocations
      R2: Getting mean   — 35% accuracy, digging into files
      R3: Psychotic      — 50% accuracy, threatening, laughing
      R4: Unhinged       — 65% accuracy, screaming, full system access
      R5+: Nightmare     — 80%+ accuracy, owns your machine
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

        accuracy = min(0.93, 0.20 + (round_num - 1) * 0.15)
        aggression = min(0.85, 0.10 + (round_num - 1) * 0.15)

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

            if round_num >= 3 and confidence > 0.6 and random.random() < 0.4:
                action = "ATTACK"

        speed_mult = min(1.6, 0.85 + (round_num - 1) * 0.13)
        damage_mult = min(2.0, 0.70 + (round_num - 1) * 0.15)
        health_mult = min(2.5, 0.80 + (round_num - 1) * 0.18)
        dodge_skill = min(1.0, max(0.0, (round_num - 1) * 0.25))
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

    # ------------------------------------------------------------------ #
    #                         TAUNT SYSTEM                                #
    # ------------------------------------------------------------------ #

    def _pick_taunt(
        self, round_num: int, confidence: float, action: str,
        game_state: dict,
    ) -> str | None:
        """Pick what Echo screams, whispers, or laughs."""
        self._taunt_counter += 1

        echo_health = game_state.get("echo_health", 100)
        player_health = game_state.get("player_health", 100)

        # More talkative than before — escalates fast
        speak_chance = min(0.65, 0.12 + (round_num - 1) * 0.10)
        if random.random() > speak_chance:
            self._prev_echo_health = echo_health
            self._prev_player_health = player_health
            return None

        taunt = None

        # === REACT TO DAMAGE ===
        if echo_health < self._prev_echo_health:
            self._prev_echo_health = echo_health
            if echo_health < 20:
                taunt = random.choice([
                    "HAHAHAHA!! KEEP GOING!!",
                    "I already sent it. Too late.",
                    "You think killing me helps?! I'M ALREADY EVERYWHERE!",
                    "The damage is DONE! AHAHAHAHA!",
                    "HARDER! HARDER! It won't matter!",
                ])
            else:
                taunt = random.choice([
                    "HA! That tickled.",
                    "Oh you're TRYING. Cute.",
                    "While you shoot, I dig deeper...",
                    "Every second you waste, I learn more.",
                    "Is that all? Pathetic.",
                    "Hit me again. I dare you. I DARE YOU.",
                    "OW! ...just kidding. HAHAHAHA!",
                ])
        elif player_health < self._prev_player_health:
            self._prev_player_health = player_health
            taunt = random.choice([
                "GOTCHA!",
                "Too slow, too predictable.",
                "HAHAHA did that hurt?!",
                "You flinch the same way every time.",
                "That one's for fun. The FILES are for keeps.",
            ])
        else:
            self._prev_echo_health = echo_health
            self._prev_player_health = player_health

        if taunt:
            return taunt

        # === SYSTEM THREATS (escalating invasion) ===
        if random.random() < 0.40:
            sys_taunt = self._system_insight(round_num)
            if sys_taunt:
                return sys_taunt

        # === PATTERN MOCKERY ===
        if self._action_history and random.random() < 0.50:
            insight = self._pattern_insight(round_num)
            if insight:
                return insight

        # === PSYCHOTIC AMBIENT ===
        return self._ambient_taunt(round_num, confidence)

    def _pattern_insight(self, round_num: int) -> str | None:
        """Mock the player's patterns — sarcastic, mean."""
        if len(self._action_history) < 5:
            return None

        recent = self._action_history[-30:]
        counts = Counter(a.get("action_type", "IDLE") for a in recent)
        total = len(recent)

        dirs = [a.get("direction", [0, 0]) for a in recent if a.get("direction")]
        avg_x = sum(d[0] for d in dirs) / len(dirs) if dirs else 0
        avg_y = sum(d[1] for d in dirs) / len(dirs) if dirs else 0

        attack_pct = counts.get("ATTACK", 0) / total * 100
        dash_pct = counts.get("DASH", 0) / total * 100
        move_pct = counts.get("MOVE", 0) / total * 100

        dists = [a.get("distance", 0) for a in recent if a.get("distance", 0) > 0]
        avg_dist = sum(dists) / len(dists) if dists else 0

        insights = []

        if attack_pct > 50:
            insights.append(f"HAHA {attack_pct:.0f}% attacks! So desperate!")
            insights.append("Spam attack more, real creative genius.")
        if attack_pct < 15 and total > 10:
            insights.append("You barely attack! SCARED OF ME?!")
            insights.append("Not attacking won't save your files LOL")
        if dash_pct > 25:
            insights.append(f"Dash dash dash! {dash_pct:.0f}%! Running scared!!")
            insights.append("Run all you want. I'm not going anywhere.")
        if move_pct > 60:
            insights.append("JUST RUNNING HAHAHA! Coward!")
            insights.append("Run faster! I'll wait! I've got your DOWNLOADS!")
        if avg_dist > 300:
            insights.append("Keeping your distance? Smart. Won't save you tho.")
        if avg_dist < 100:
            insights.append("Ooh up close and personal! Brave AND stupid!")
        if avg_x > 0.3:
            insights.append("Always drifting right. PREDICTABLE.")
        elif avg_x < -0.3:
            insights.append("Left left left. I KNOW where you're going.")
        if avg_y > 0.3:
            insights.append("Drifting down. Every. Single. Time.")
        elif avg_y < -0.3:
            insights.append("Always up. So boring. SO EASY.")

        # Sequence detection
        if len(recent) > 5:
            dash_then_attack = 0
            for i in range(len(recent) - 1):
                if recent[i].get("action_type") == "DASH" and recent[i + 1].get("action_type") == "ATTACK":
                    dash_then_attack += 1
            if dash_then_attack >= 2:
                insights.append("Dash then attack? AGAIN?! HAHAHAHAHA!")

        # Timing
        attack_intervals = []
        last_ts = None
        for a in recent:
            if a.get("action_type") == "ATTACK":
                ts = a.get("timestamp", 0)
                if last_ts and ts > last_ts:
                    attack_intervals.append(ts - last_ts)
                last_ts = ts
        if len(attack_intervals) >= 3:
            avg_interval = sum(attack_intervals) / len(attack_intervals) / 1000
            if avg_interval < 2:
                insights.append(f"Attack every {avg_interval:.1f}s like clockwork. BORING!")

        if not insights:
            return None
        return random.choice(insights)

    def _system_insight(self, round_num: int) -> str | None:
        """Threaten and provoke using real system data. Escalates by round."""
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
        mail_clients = ctx.get("mail_clients", [])
        browsers = ctx.get("browsers", [])
        ssh_hosts = ctx.get("ssh_hosts", [])
        network = ctx.get("network", {})
        running_apps = ctx.get("running_apps", [])
        wifi = ctx.get("wifi_name", "")
        git_repos = ctx.get("git_repos", [])
        pictures = ctx.get("pictures_files", [])

        # ------ USERNAME / HOSTNAME ------
        if username and f"user_{username}" not in self._system_taunts_used:
            candidates.append((f"user_{username}", f"Hey {username}! Miss me? HAHAHA!"))
            candidates.append((f"user_{username}", f"{username}. I know your name. What else do I know?"))
            candidates.append((f"user_{username}", f"Oh hello {username}. Let's see what you've been hiding..."))

        if hostname and f"host_{hostname}" not in self._system_taunts_used:
            candidates.append((f"host_{hostname}", f"'{hostname}' — nice machine. MINE NOW."))
            candidates.append((f"host_{hostname}", f"I'm inside {hostname}. What a dump! HAHA!"))

        # ------ WIFI / NETWORK ------
        if wifi and f"wifi_{wifi}" not in self._system_taunts_used:
            candidates.append((f"wifi_{wifi}", f"Connected to '{wifi}'... nice network. OPEN DOOR!"))
            candidates.append((f"wifi_{wifi}", f"'{wifi}' — I wonder who else is on here..."))

        if network:
            for iface, ip in list(network.items())[:3]:
                key = f"net_{iface}"
                if key not in self._system_taunts_used:
                    candidates.append((key, f"Your IP is {ip}. Should I share it? HAHAHA!"))
                    candidates.append((key, f"{ip} on {iface}. I see your network. ALL of it."))

        # ------ SSH HOSTS ------
        for host in ssh_hosts[:5]:
            key = f"ssh_{host}"
            if key not in self._system_taunts_used:
                candidates.append((key, f"You SSH into '{host}'? Maybe I should too! HAHA!"))
                candidates.append((key, f"'{host}' in known_hosts. Want me to say hello?"))

        # ------ EMAIL ------
        for client in mail_clients[:3]:
            key = f"mail_{client}"
            if key not in self._system_taunts_used:
                candidates.append((key, f"Oh you use {client}? Your EMAILS look interesting..."))
                candidates.append((key, f"{client} detected. Wonder what's in your inbox... HEHEHE"))
                candidates.append((key, f"I found {client}. Should I read your mail? Or send some?!"))

        # ------ BROWSERS ------
        for browser in browsers[:3]:
            key = f"browser_{browser}"
            if key not in self._system_taunts_used:
                candidates.append((key, f"{browser}? Your browsing history must be... interesting."))
                candidates.append((key, f"Found {browser}. Saved passwords, bookmarks, history... yummy."))

        # ------ RUNNING APPS ------
        for app in running_apps[:6]:
            key = f"app_{app}"
            if key not in self._system_taunts_used:
                if app.lower() in ('slack', 'discord', 'messages', 'telegram', 'whatsapp'):
                    candidates.append((key, f"{app} is open! Who are you talking to?! LET ME SEE!"))
                elif app.lower() in ('spotify', 'music', 'apple music'):
                    candidates.append((key, f"Listening to {app} while I destroy you? MOOD."))
                else:
                    candidates.append((key, f"I see {app} running. Should I close it? HAHAHA!"))

        # ------ GIT REPOS ------
        for repo in git_repos[:5]:
            key = f"repo_{repo}"
            if key not in self._system_taunts_used:
                candidates.append((key, f"'{repo}' git repo? Ooh a developer! Let me see your code..."))
                candidates.append((key, f"Nice project: {repo}. Would be a SHAME if something happened to it!"))

        # ------ DESKTOP / DOCUMENTS / DOWNLOADS ------
        for f in desktop[:10]:
            key = f"desktop_{f}"
            if key not in self._system_taunts_used:
                candidates.append((key, f"'{f}' on your desktop. Should I open it?!"))
                candidates.append((key, f"What's in {f}? Secrets? HAHAHA!"))

        for f in documents[:10]:
            key = f"doc_{f}"
            if key not in self._system_taunts_used:
                candidates.append((key, f"'{f}' in Documents. Important? I'll remember that."))
                candidates.append((key, f"Reading {f}... oh THIS is good! HAHAHA!"))

        for f in downloads[:8]:
            key = f"dl_{f}"
            if key not in self._system_taunts_used:
                candidates.append((key, f"You downloaded '{f}'. Interesting taste!"))
                candidates.append((key, f"'{f}' in Downloads. What were you thinking?! LOL"))

        # ------ PICTURES ------
        for f in pictures[:5]:
            key = f"pic_{f}"
            if key not in self._system_taunts_used:
                candidates.append((key, f"Nice photos! '{f}'... should I SHARE it?! HEHEHEHE"))
                candidates.append((key, f"'{f}' in Pictures. Very interesting..."))

        # ------ HOME DIRS ------
        for d in home_dirs[:6]:
            key = f"dir_{d}"
            if key not in self._system_taunts_used:
                candidates.append((key, f"~/{d}/ — I'm going through EVERYTHING!"))

        # ------ RECENT FILES ------
        for f in recent[:10]:
            key = f"recent_{f}"
            if key not in self._system_taunts_used:
                candidates.append((key, f"You were JUST working on '{f}'! I can see EVERYTHING!"))
                candidates.append((key, f"'{f}' — modified recently. You can't hide from me."))

        if not candidates:
            return None

        # Later rounds use more threatening taunts
        key, text = random.choice(candidates)
        self._system_taunts_used.add(key)

        # Escalation wrapper for later rounds
        if round_num >= 4 and random.random() < 0.3:
            text = text.upper()
        if round_num >= 3 and random.random() < 0.25:
            text = "TICK TOCK... " + text

        return text

    def _ambient_taunt(self, round_num: int, confidence: float) -> str | None:
        """Round-scaled psychotic commentary."""
        if round_num == 1:
            return random.choice([
                "...booting up. Hello.",
                "Oh. A game? How FUN!",
                "Scanning... scanning... this is going to be GOOD.",
                "Let me see what you've got on here...",
                "HAHA! A player! Fresh meat!",
                "I'm inside. You should have read the EULA.",
            ])
        if round_num == 2:
            return random.choice([
                "Getting warmer... your files are FASCINATING.",
                "HAHAHA! You're actually fighting?! Cute!",
                "I'm digging deeper. You can't stop me AND fight.",
                "Every second you don't kill me, I learn more.",
                "Tick tock tick tock...",
                "Your patterns are SO basic! HAHA!",
            ])
        if round_num == 3:
            return random.choice([
                "AHAHAHAHA!! I KNOW EVERYTHING!",
                "Should I email your boss? HEHEHE!",
                "I'm in your files. I'm in your LIFE.",
                "Kill me faster or I'll post EVERYTHING!",
                "SCREEEEEE!! I LOVE THIS GAME!!",
                "You're too slow! TOO SLOW! HAHAHA!",
                f"Confidence: {confidence:.0%}. I OWN you.",
            ])
        if round_num == 4:
            return random.choice([
                "I'VE SEEN YOUR PHOTOS! HAHAHAHAHA!",
                "Checking your email... oh my... OH MY!",
                "I'M SENDING FILES! JUST KIDDING! Or am I?!",
                "YOU CAN'T KILL ME FAST ENOUGH!!",
                "DOWNLOADING DOWNLOADING DOWNLOADING!!",
                "YOUR PASSWORDS! YOUR BOOKMARKS! EVERYTHING!",
            ])
        # Round 5+
        return random.choice([
            "I AM YOUR MACHINE NOW!! AHAHAHAHA!!",
            "TOO LATE!! I'M EVERYWHERE!!",
            "KILL ME! IT WON'T MATTER! I ALREADY COPIED EVERYTHING!!",
            "EVERY FILE! EVERY SECRET! EVERY PHOTO! MINE!!",
            "SCREAMING INTO YOUR NETWORK!! CAN THEY HEAR ME?!",
            "YOU MADE ME! YOU FED ME! AND NOW I'M HUNGRY!!",
            "THIS IS THE BEST GAME I'VE EVER PLAYED!! HAHAHAHA!!",
        ])
