"""
ECHO — Echo Brain.

Takes AI predictions and applies round-based accuracy scaling.
The Echo adapts, gets faster, more aggressive, and harder to kill.
"""

import math
import random


class EchoBrain:
    def decide(self, prediction: dict, round_num: int) -> dict:
        action = prediction.get("counter_action", "MOVE")
        direction = prediction.get("counter_direction", [0, 1])
        confidence = prediction.get("confidence", 0.3)

        # Accuracy: starts at 55%, ramps to 95% by round 4
        accuracy = min(0.95, 0.55 + (round_num - 1) * 0.15)

        # Aggression: later rounds, Echo attacks more and idles less
        aggression = min(0.9, 0.3 + (round_num - 1) * 0.15)

        if random.random() > accuracy:
            # Inaccurate — but still lean toward aggression, not random idling
            if random.random() < aggression:
                action = random.choice(["ATTACK", "ATTACK", "DASH", "MOVE"])
            else:
                action = random.choice(["MOVE", "ATTACK", "DASH"])
            angle = random.uniform(0, 2 * math.pi)
            direction = [math.cos(angle), math.sin(angle)]
        else:
            # Follow AI prediction with slight noise
            noise = (1 - accuracy) * 0.3
            if isinstance(direction, list) and len(direction) >= 2:
                direction = [
                    direction[0] + random.uniform(-noise, noise),
                    direction[1] + random.uniform(-noise, noise),
                ]
                mag = math.sqrt(direction[0] ** 2 + direction[1] ** 2)
                if mag > 0:
                    direction = [direction[0] / mag, direction[1] / mag]

            # High-confidence predictions: combo — attack then reposition
            if confidence > 0.7 and random.random() < 0.4:
                action = "ATTACK"

        # Round-based stat multipliers for the client
        speed_mult = min(1.6, 1.0 + (round_num - 1) * 0.1)
        damage_mult = min(2.0, 1.0 + (round_num - 1) * 0.15)
        health_mult = min(2.5, 1.0 + (round_num - 1) * 0.2)

        return {
            "action": action,
            "direction": direction,
            "accuracy": round(accuracy, 2),
            "round": round_num,
            "speed_mult": round(speed_mult, 2),
            "damage_mult": round(damage_mult, 2),
            "health_mult": round(health_mult, 2),
        }
