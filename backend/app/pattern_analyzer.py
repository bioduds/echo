"""
ECHO — Pattern Analyzer.

Uses OLMo 2 to analyze player behavior sequences
and predict their next actions in the arena.
"""

import httpx
import json
import logging
import os
from collections import Counter

logger = logging.getLogger("echo.pattern_analyzer")

OLLAMA_HOST = os.environ.get("OLLAMA_HOST", "http://ollama:11434")

PREDICT_PROMPT = """You are an AI gaming opponent analyzing a player's behavior in a 2D arena combat game.

Actions: MOVE (navigate), ATTACK (fire projectile), DASH (quick burst), IDLE (standing still).

The player's recent actions (most recent last):
{action_history}

Current state:
- Player at ({px:.0f}, {py:.0f}), health {ph:.0f}%
- Echo at ({ex:.0f}, {ey:.0f}), health {eh:.0f}%
- Distance: {dist:.0f}px

Predict the player's next action and choose a counter-move.

Respond with ONLY valid JSON:
{{
  "predicted_player_action": "MOVE|ATTACK|DASH|IDLE",
  "predicted_direction": [x, y],
  "counter_action": "MOVE|ATTACK|DASH|IDLE",
  "counter_direction": [x, y],
  "confidence": 0.0-1.0
}}"""

PROFILE_PROMPT = """You are a psychological profiler analyzing a gamer's combat behavior in an arena fighting game called ECHO. You are the AI mirror that learns to fight like the player.

Action history ({total} actions across {rounds} round(s)):
{history_summary}

Stats:
- Attacks: {attack_pct}% | Moves: {move_pct}% | Dashes: {dash_pct}% | Idle: {idle_pct}%
- Avg engagement distance: {avg_dist:.0f}px

Generate:
1. A behavioral profile (2-3 sentences analyzing their playstyle, specific patterns, tendencies)
2. A taunting message FROM the Echo mirror — confident, slightly menacing, referencing specific patterns you observed

Respond with ONLY valid JSON:
{{
  "profile": "behavioral analysis",
  "taunt": "the echo's taunt referencing what it learned",
  "playstyle": "aggressive|defensive|tactical|erratic|cautious",
  "predictability": 0.0-1.0
}}"""


class PatternAnalyzer:
    def __init__(self):
        self._sessions: dict[str, list[dict]] = {}

    def create_session(self, session_id: str):
        self._sessions[session_id] = []

    def record_action(self, session_id: str, action: dict):
        if session_id not in self._sessions:
            self._sessions[session_id] = []
        self._sessions[session_id].append(action)
        if len(self._sessions[session_id]) > 5000:
            self._sessions[session_id] = self._sessions[session_id][-2500:]

    async def predict_player(self, session_id: str, game_state: dict) -> dict:
        history = self._sessions.get(session_id, [])
        if len(history) < 3:
            return self._fallback_prediction(history, game_state)

        recent = history[-20:]
        lines = []
        for a in recent:
            d = a.get("direction", [0, 0])
            lines.append(f"  {a.get('action_type', 'IDLE')} dir=[{d[0]:.1f},{d[1]:.1f}]")

        pp = game_state.get("player_pos", [0, 0])
        ep = game_state.get("echo_pos", [0, 0])
        dist = game_state.get("distance", 0)

        prompt = PREDICT_PROMPT.format(
            action_history="\n".join(lines),
            px=pp[0], py=pp[1], ph=game_state.get("player_health", 100),
            ex=ep[0], ey=ep[1], eh=game_state.get("echo_health", 100),
            dist=dist,
        )

        try:
            async with httpx.AsyncClient(timeout=8.0) as client:
                resp = await client.post(
                    f"{OLLAMA_HOST}/api/generate",
                    json={
                        "model": "smollm2:1.7b",
                        "prompt": prompt,
                        "stream": False,
                        "options": {"temperature": 0.3, "num_predict": 150},
                    },
                )
                resp.raise_for_status()
                raw = resp.json().get("response", "")
            return self._parse_prediction(raw)
        except Exception as e:
            logger.error("Prediction failed: %s", e)
            return self._fallback_prediction(history, game_state)

    async def generate_profile(self, session_id: str, round_num: int) -> dict:
        history = self._sessions.get(session_id, [])
        if not history:
            return {
                "profile": "Not enough data yet.",
                "taunt": "I'm watching you...",
                "playstyle": "unknown",
                "predictability": 0.0,
            }

        total = len(history)
        counts = Counter(a.get("action_type", "IDLE") for a in history)
        distances = [a.get("distance", 0) for a in history if a.get("distance", 0) > 0]
        avg_dist = sum(distances) / len(distances) if distances else 0

        recent_lines = []
        for a in history[-40:]:
            d = a.get("direction", [0, 0])
            recent_lines.append(
                f"  R{a.get('round', '?')}: {a.get('action_type', 'IDLE')} dir=[{d[0]:.1f},{d[1]:.1f}]"
            )

        prompt = PROFILE_PROMPT.format(
            total=total,
            rounds=round_num,
            history_summary="\n".join(recent_lines),
            attack_pct=round(counts.get("ATTACK", 0) / total * 100) if total else 0,
            move_pct=round(counts.get("MOVE", 0) / total * 100) if total else 0,
            dash_pct=round(counts.get("DASH", 0) / total * 100) if total else 0,
            idle_pct=round(counts.get("IDLE", 0) / total * 100) if total else 0,
            avg_dist=avg_dist,
        )

        try:
            async with httpx.AsyncClient(timeout=20.0) as client:
                resp = await client.post(
                    f"{OLLAMA_HOST}/api/generate",
                    json={
                        "model": "smollm2:1.7b",
                        "prompt": prompt,
                        "stream": False,
                        "options": {"temperature": 0.6, "num_predict": 300},
                    },
                )
                resp.raise_for_status()
                raw = resp.json().get("response", "")
            return self._parse_profile(raw)
        except Exception as e:
            logger.error("Profile generation failed: %s", e)
            return {
                "profile": "Analysis in progress...",
                "taunt": "You can't hide your patterns forever.",
                "playstyle": "unknown",
                "predictability": 0.5,
            }

    def _parse_prediction(self, raw: str) -> dict:
        try:
            start = raw.find("{")
            end = raw.rfind("}") + 1
            if start >= 0 and end > start:
                parsed = json.loads(raw[start:end])
                valid = {"MOVE", "ATTACK", "DASH", "IDLE"}
                action = parsed.get("counter_action", "MOVE").upper()
                direction = parsed.get("counter_direction", [0, 1])
                return {
                    "predicted_player_action": parsed.get("predicted_player_action", "MOVE"),
                    "counter_action": action if action in valid else "MOVE",
                    "counter_direction": direction if isinstance(direction, list) and len(direction) >= 2 else [0, 1],
                    "confidence": max(0, min(1, float(parsed.get("confidence", 0.5)))),
                }
        except (json.JSONDecodeError, ValueError, TypeError):
            pass
        return {"counter_action": "MOVE", "counter_direction": [0, -1], "confidence": 0.1}

    def _fallback_prediction(self, history: list, game_state: dict) -> dict:
        if history:
            counts = Counter(a.get("action_type", "IDLE") for a in history[-10:])
            most_common = counts.most_common(1)[0][0]
            # Counter: if they mostly move, attack; if they attack, dodge
            counter = "ATTACK" if most_common == "MOVE" else "MOVE"
            pp = game_state.get("player_pos", [0, 0])
            ep = game_state.get("echo_pos", [0, 0])
            dx = pp[0] - ep[0]
            dy = pp[1] - ep[1]
            mag = (dx ** 2 + dy ** 2) ** 0.5
            if mag > 0:
                dx, dy = dx / mag, dy / mag
            return {"counter_action": counter, "counter_direction": [dx, dy], "confidence": 0.2}
        return {"counter_action": "MOVE", "counter_direction": [0, -1], "confidence": 0.1}

    def _parse_profile(self, raw: str) -> dict:
        try:
            start = raw.find("{")
            end = raw.rfind("}") + 1
            if start >= 0 and end > start:
                parsed = json.loads(raw[start:end])
                return {
                    "profile": parsed.get("profile", "Analysis unavailable."),
                    "taunt": parsed.get("taunt", "I see you."),
                    "playstyle": parsed.get("playstyle", "unknown"),
                    "predictability": max(0, min(1, float(parsed.get("predictability", 0.5)))),
                }
        except (json.JSONDecodeError, ValueError, TypeError):
            pass
        return {
            "profile": "Analysis unavailable.",
            "taunt": "Interesting patterns...",
            "playstyle": "unknown",
            "predictability": 0.5,
        }
