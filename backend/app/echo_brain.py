"""
ECHO — Echo Brain.

Takes AI predictions and applies round-based accuracy scaling.
The Echo adapts, gets faster, more aggressive, and harder to kill.
"""

import math
import random


class EchoBrain:
    """Difficulty curve:
      R1: Punching bag  — 20% accuracy, no buffs, mostly wanders
      R2: Waking up     — 35% accuracy, slight buffs, starts countering
      R3: Learning      — 50% accuracy, noticeable speed/damage
      R4: Dangerous     — 65% accuracy, aggressive, starts dodging well
      R5: Mirror        — 80% accuracy, fast, hard-hitting, tanky
      R6+: Nightmare    — 90%+ accuracy, max scaling
    """

    def decide(self, prediction: dict, round_num: int) -> dict:
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
        }
