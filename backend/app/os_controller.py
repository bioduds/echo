"""
ECHO — OS Controller (Phase 10 Effects)

Triggers macOS system-level effects during Phase 10 via osascript.
All payloads are game-defined strings — no user input is passed to the shell.
Failures are logged but never propagated (fire-and-forget).

Requires macOS Accessibility or Notification permissions granted by the user
(the disclaimer screen informs the player before they proceed).
"""

from __future__ import annotations

import logging
import subprocess
from enum import Enum

logger = logging.getLogger("echo.os_controller")

_OSASCRIPT_TIMEOUT = 5  # seconds — enough for any legit AppleScript


class OsEffect(str, Enum):
    NOTIFICATION          = "notification"
    OPEN_FINDER_DOCUMENTS = "open_finder_documents"
    TERMINAL_MESSAGE      = "terminal_message"
    WALLPAPER_DARK        = "wallpaper_dark"
    WALLPAPER_RESTORE     = "wallpaper_restore"


# Pre-canned game strings — never built from user input
_EFFECTS: dict[OsEffect, tuple[str, str, str]] = {
    # effect: (script, success_log, fail_log)
    OsEffect.NOTIFICATION: (
        # Notification: "Echo is watching." — most permissive, works without full disk access
        'display notification "I am watching." with title "ECHO" subtitle "System Alert"',
        "OS notification sent",
        "OS notification failed (permissions?)",
    ),
    OsEffect.OPEN_FINDER_DOCUMENTS: (
        'tell application "Finder" to open (path to documents folder)',
        "Finder Documents opened",
        "Finder open failed",
    ),
    OsEffect.TERMINAL_MESSAGE: (
        # Opens a new Terminal window and types the taunt
        'tell application "Terminal" to do script "echo \'Your files belong to me\'"',
        "Terminal message sent",
        "Terminal message failed",
    ),
    OsEffect.WALLPAPER_DARK: (
        # Set all desktops to solid black (macOS ships this wallpaper)
        'tell application "System Events" to tell every desktop '
        'to set picture to "/Library/Desktop Pictures/Solid Colors/Black.png"',
        "Wallpaper set to black",
        "Wallpaper change failed (permissions?)",
    ),
    OsEffect.WALLPAPER_RESTORE: (
        # Try Sonoma first; silent failure on older OS is fine
        'tell application "System Events" to tell every desktop '
        'to set picture to "/Library/Desktop Pictures/macOS Sonoma.heic"',
        "Wallpaper restored",
        "Wallpaper restore failed (non-fatal)",
    ),
}


def _run_applescript(script: str) -> bool:
    """Execute an AppleScript snippet via osascript. Returns True on success."""
    try:
        result = subprocess.run(
            ["osascript", "-e", script],
            capture_output=True,
            text=True,
            timeout=_OSASCRIPT_TIMEOUT,
        )
        if result.returncode != 0:
            logger.warning("osascript stderr: %s", result.stderr.strip())
            return False
        return True
    except subprocess.TimeoutExpired:
        logger.warning("osascript timed out after %ds", _OSASCRIPT_TIMEOUT)
        return False
    except FileNotFoundError:
        logger.warning("osascript not found — non-macOS environment")
        return False
    except Exception as exc:
        logger.warning("osascript unexpected error: %s", exc)
        return False


def trigger_effect(effect: OsEffect) -> dict:
    """
    Fire an OS-level effect.  Returns {"effect": str, "success": bool}.
    Never raises — all failures are swallowed and logged.
    """
    entry = _EFFECTS.get(effect)
    if not entry:
        return {"effect": effect, "success": False, "reason": "unknown effect"}

    script, ok_msg, fail_msg = entry
    success = _run_applescript(script)
    logger.info(ok_msg if success else fail_msg)
    return {"effect": effect, "success": success}


def trigger_phase10_sequence() -> list[dict]:
    """
    Fire the full Phase 10 OS invasion sequence.
    Returns results for each step.
    """
    sequence = [
        OsEffect.NOTIFICATION,
        OsEffect.OPEN_FINDER_DOCUMENTS,
        OsEffect.WALLPAPER_DARK,
        OsEffect.TERMINAL_MESSAGE,
    ]
    return [trigger_effect(e) for e in sequence]
