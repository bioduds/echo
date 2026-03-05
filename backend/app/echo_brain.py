"""
ECHO — Echo Brain.

Takes AI predictions and applies round-based accuracy scaling.
Early rounds: noisy, semi-random. Later rounds: precise, deadly.
"""

import math
import random


class EchoBrain:
    def decide(self, prediction: dict, round_num: int) -> dict:
        action = prediction.get("counter_action", "MOVE")
        direction = prediction.get("counter_direction", [0, 1])

        # Round-based accuracy: starts at 30%, caps at 95%
        accuracy = min(0.95, 0.30 + (round_num - 1) * 0.12)

        if random.random() > accuracy:
            # Random override — early rounds are chaotic
            action = random.choice(["MOVE", "ATTACK", "DASH", "IDLE"])
            angle = random.uniform(0, 2 * math.pi)
            direction = [math.cos(angle), math.sin(angle)]
        else:
            # Follow AI prediction with slight noise
            noise = (1 - accuracy) * 0.4
            if isinstance(direction, list) and len(direction) >= 2:
                direction = [
                    direction[0] + random.uniform(-noise, noise),
                    direction[1] + random.uniform(-noise, noise),
                ]
                mag = math.sqrt(direction[0] ** 2 + direction[1] ** 2)
                if mag > 0:
                    direction = [direction[0] / mag, direction[1] / mag]

        return {
            "action": action,
            "direction": direction,
            "accuracy": round(accuracy, 2),
            "round": round_num,
        }
