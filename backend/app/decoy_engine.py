"""
ECHO — Decoy and Evidence Engine

Provides synthetic fallback evidence when real scanner data is sparse or
privacy-blocked.  Maintains a growing per-session dossier that deepens
across rounds and powers Phase 11's full-exposure profile dump.

Architecture:
  - Decoy pools: static typed lists of plausible artifacts per category
  - SessionEvidence: per-session accumulator, absorbs real data from every round
  - DecoyEngine: merges real + decoy data, builds profile dump on demand
"""

from __future__ import annotations

import random
import time
from dataclasses import dataclass, field
from typing import Any


# ─────────────────────────────────────────────────────────────────────────────
# Decoy Pools — platform-appropriate macOS developer artifacts
#   Tiered early/mid/late so revealed content escalates with phase.
# ─────────────────────────────────────────────────────────────────────────────

_BROWSER_EARLY = [
    "github.com/trending",
    "stackoverflow.com/questions",
    "docs.python.org/3",
    "news.ycombinator.com",
    "youtube.com/watch",
]

_BROWSER_MID = [
    "localhost:3000/dashboard",
    "localhost:8080/api/v1/admin",
    "app.slack.com/client",
    "mail.google.com/mail/u/0",
    "console.aws.amazon.com/console",
    "notion.so/workspace",
]

_BROWSER_LATE = [
    "accounts.google.com/signin/recovery",
    "github.com/settings/tokens/new",
    "console.aws.amazon.com/iam/home#/users",
    "localhost:5432/pgadmin",
    "vault.company.internal/ui",
    "jenkins.internal/job/prod-deploy",
]

_EMAIL_EARLY = [
    "Re: Weekly standup notes",
    "GitHub: pull request review requested",
    "Your invoice is ready",
    "Meeting invitation: Q1 planning",
]

_EMAIL_MID = [
    "Re: Salary review Q4",
    "Confidential: Contract renewal terms",
    "AWS cost alert — unusual spending",
    "Re: Incident postmortem",
    "Password reset for your account",
]

_EMAIL_LATE = [
    "CONFIDENTIAL: Legal matter — please respond",
    "Security alert: new device sign-in to your account",
    "Re: Performance improvement plan",
    "NDA breach flag — action required",
    "Re: Severance package details",
]

_GIT_EARLY = [
    "fix: null pointer in auth module",
    "feat: add dark mode toggle",
    "chore: update dependencies",
    "refactor: split oversized component",
]

_GIT_MID = [
    "hotfix: prod db migration — DO NOT SQUASH",
    "temp: disable rate limiting for demo",
    "WIP: export user data — draft",
    "fix: admin panel visible to non-admins",
]

_GIT_LATE = [
    "WIP: bypass auth check for testing — REMOVE BEFORE MERGE",
    "shame: hardcoded credentials removed (hopefully)",
    "hotfix: private key accidentally committed to main",
    "temp: logging user emails for debug — MUST REMOVE",
]

_DOC_EARLY = [
    "Meeting notes — product roadmap.md",
    "Shopping list.txt",
    "Travel itinerary.pdf",
    "Book notes — chapter 3.md",
]

_DOC_MID = [
    "Budget 2025.xlsx",
    "tax_return_draft.pdf",
    "Untitled Document — 47 revisions",
    "Medical history notes.txt",
]

_DOC_LATE = [
    "Passwords (backup).txt — 23 entries",
    "DO NOT OPEN — personal.zip",
    "Legal docs — settlement agreement.pdf",
    "therapy_notes_2024.txt",
]

_CONTACT_POOL = [
    "Alex (work)",
    "Mom",
    "Dr. Williams",
    "Marcus T.",
    "Sarah (HR)",
    "Jordan — college friend",
]

_SSH_EARLY = [
    "github.com",
    "gitlab.com",
    "bitbucket.org",
]

_SSH_MID = [
    "db.prod.internal",
    "bastion.company.internal",
    "ec2-54-203-aws.compute-1.amazonaws.com",
]

_SSH_LATE = [
    "prod-database-01.internal",
    "secrets.vault.internal",
    "backup-server-nightly.internal",
]

_POOL_MAP: dict[str, list[list[str]]] = {
    "browser":  [_BROWSER_EARLY,  _BROWSER_MID,  _BROWSER_LATE],
    "email":    [_EMAIL_EARLY,    _EMAIL_MID,    _EMAIL_LATE],
    "git":      [_GIT_EARLY,      _GIT_MID,      _GIT_LATE],
    "doc":      [_DOC_EARLY,      _DOC_MID,      _DOC_LATE],
    "contact":  [_CONTACT_POOL,   _CONTACT_POOL, _CONTACT_POOL],
    "ssh":      [_SSH_EARLY,      _SSH_MID,      _SSH_LATE],
}


# ─────────────────────────────────────────────────────────────────────────────
# SessionEvidence — growing per-session dossier
# ─────────────────────────────────────────────────────────────────────────────

@dataclass
class SessionEvidence:
    session_id: str
    created_at: float = field(default_factory=time.time)
    rounds_completed: int = 0

    # Accumulated real artifacts
    browser: list[str] = field(default_factory=list)
    emails: list[str] = field(default_factory=list)
    git_commits: list[str] = field(default_factory=list)
    docs: list[str] = field(default_factory=list)
    recent_files: list[str] = field(default_factory=list)
    contacts: list[str] = field(default_factory=list)
    ssh_hosts: list[str] = field(default_factory=list)
    password_managers: list[str] = field(default_factory=list)

    # Metadata
    username: str = "user"
    hostname: str = "machine"
    total_files_seen: int = 0
    repos_found: int = 0
    contact_count_override: int = 0

    # Derived
    dominant_category: str = "Browser"
    data_richness: float = 0.0  # fraction of categories with real data

    def accumulate(self, real_ctx: dict, round_num: int) -> None:
        """Absorb real scanner context into the session bag."""
        self.rounds_completed = max(self.rounds_completed, round_num)

        def _extend_dedup(bag: list[str], new_items: list[str], cap: int = 24) -> None:
            seen = set(bag)
            for item in new_items:
                s = str(item).strip()
                if s and s not in seen and len(bag) < cap:
                    bag.append(s)
                    seen.add(s)

        _extend_dedup(self.browser,           [x for x in real_ctx.get("browser_history",   []) if x])
        _extend_dedup(self.emails,            [x for x in real_ctx.get("email_subjects",     []) if x])
        _extend_dedup(self.git_commits,       [x for x in real_ctx.get("git_commits",         []) if x])
        _extend_dedup(self.docs,              [x for x in real_ctx.get("doc_samples",          []) if x])
        _extend_dedup(self.recent_files,      [x for x in real_ctx.get("recent_files",         []) if x])
        _extend_dedup(self.contacts,          [x for x in real_ctx.get("contacts",             []) if x])
        _extend_dedup(self.ssh_hosts,         [x for x in real_ctx.get("ssh_hosts",            []) if x])
        _extend_dedup(self.password_managers, [x for x in real_ctx.get("password_managers",    []) if x])

        if real_ctx.get("username"):
            self.username = str(real_ctx["username"])
        if real_ctx.get("hostname"):
            self.hostname = str(real_ctx["hostname"])

        raw_files = (
            len(real_ctx.get("desktop_files", []))
            + len(real_ctx.get("document_files", []))
            + len(real_ctx.get("download_files", []))
        )
        if raw_files:
            self.total_files_seen = max(self.total_files_seen, raw_files)

        if real_ctx.get("contacts"):
            self.contact_count_override = max(self.contact_count_override, len(real_ctx["contacts"]))

        self.repos_found = max(self.repos_found, len(self.git_commits) // 2 + 1)

        # Derived stats
        real_cats = sum(
            1 for bag in [self.browser, self.emails, self.git_commits, self.docs, self.ssh_hosts]
            if bag
        )
        self.data_richness = min(1.0, real_cats / 5.0)

        counts = {
            "Browser":  len(self.browser),
            "Email":    len(self.emails),
            "Git":      len(self.git_commits),
            "Document": len(self.docs),
            "SSH":      len(self.ssh_hosts),
        }
        self.dominant_category = max(counts, key=lambda k: counts[k]) if any(counts.values()) else "Browser"


# ─────────────────────────────────────────────────────────────────────────────
# DecoyEngine
# ─────────────────────────────────────────────────────────────────────────────

class DecoyEngine:
    """
    Enriches real scanner context with plausible decoys when evidence is sparse,
    and maintains a growing per-session dossier for Phase 11 profile dumps.

    Thread-safety: single-threaded use only (FastAPI with one worker).
    """

    def __init__(self) -> None:
        self._sessions: dict[str, SessionEvidence] = {}

    def _get_or_create(self, session_id: str) -> SessionEvidence:
        if session_id not in self._sessions:
            self._sessions[session_id] = SessionEvidence(session_id=session_id)
        return self._sessions[session_id]

    @staticmethod
    def _phase_tier(round_num: int) -> int:
        """Map round number to pool tier: 1=early, 2=mid, 3=late."""
        if round_num <= 4:
            return 1
        if round_num <= 8:
            return 2
        return 3

    def _decoy_pool(self, category: str, round_num: int, exclude: set[str]) -> list[str]:
        """Return a shuffled, deduplicated list of decoys for the given category at this phase tier."""
        tier = self._phase_tier(round_num)
        tier_idx = tier - 1
        pool_tiers = _POOL_MAP.get(category, [[], [], []])
        # Accumulate tiers progressively (late pool includes early)
        merged: list[str] = []
        seen: set[str] = set()
        for i in range(tier_idx + 1):
            for item in pool_tiers[i]:
                if item not in seen:
                    merged.append(item)
                    seen.add(item)
        return [x for x in merged if x not in exclude]

    def enrich_context(self, session_id: str, round_num: int, real_ctx: dict) -> dict:
        """
        Absorb real scanner data into the session bag, then return an enriched
        copy of real_ctx where each sparse category is topped up with decoys.
        """
        evidence = self._get_or_create(session_id)
        evidence.accumulate(real_ctx, round_num)

        tier = self._phase_tier(round_num)
        # Minimum items to guarantee per tier (after enrichment)
        min_counts = {
            "browser":  [1, 2, 3][tier - 1],
            "email":    [0, 1, 2][tier - 1],
            "git":      [0, 1, 2][tier - 1],
            "doc":      [0, 1, 1][tier - 1],
            "ssh":      [0, 0, 1][tier - 1],
        }

        def _enrich(real: list[str], category: str) -> list[str]:
            min_needed = min_counts.get(category, 0)
            if len(real) >= min_needed:
                return real
            pool = self._decoy_pool(category, round_num, exclude=set(real))
            # Deterministic shuffle per session+round+category to avoid flickering
            rng = random.Random(f"{session_id}:{round_num}:{category}")
            rng.shuffle(pool)
            needed = min_needed - len(real)
            return real + pool[:needed]

        enriched = dict(real_ctx)
        enriched["browser_history"]  = _enrich([str(x) for x in real_ctx.get("browser_history",  []) if x], "browser")
        enriched["email_subjects"]   = _enrich([str(x) for x in real_ctx.get("email_subjects",   []) if x], "email")
        enriched["git_commits"]      = _enrich([str(x) for x in real_ctx.get("git_commits",       []) if x], "git")
        enriched["doc_samples"]      = _enrich([str(x) for x in real_ctx.get("doc_samples",       []) if x], "doc")
        enriched["ssh_hosts"]        = _enrich([str(x) for x in real_ctx.get("ssh_hosts",         []) if x], "ssh")
        return enriched

    def absorb_system_context(self, session_id: str, ctx: dict) -> None:
        """
        Called when /system_context is received (round 0, before first predict).
        Seeds the session bag with the initial scan data.
        """
        evidence = self._get_or_create(session_id)
        evidence.accumulate(ctx, round_num=0)

    def build_profile_dump(self, session_id: str) -> dict[str, Any]:
        """
        Generate the Phase 11 full-exposure profile overlay.
        Merges real accumulated data with estimates for a complete dossier.
        """
        ev = self._sessions.get(session_id)
        if not ev:
            return self._empty_profile(session_id)

        total_files = ev.total_files_seen or random.randint(1200, 3800)
        rounds = ev.rounds_completed or 1
        accuracy = min(99, 58 + rounds * 3 + int(ev.data_richness * 10))
        contact_count = ev.contact_count_override or len(ev.contacts) or random.randint(3, 12)

        profile_lines = [
            {"key": "SUBJECT",               "value": f"{ev.username}@{ev.hostname}"},
            {"key": "ROUNDS SURVIVED",       "value": str(rounds)},
            {"key": "FILES ACCESSED",        "value": str(total_files)},
            {"key": "BROWSER ARTIFACTS",     "value": str(len(ev.browser))},
            {"key": "EMAIL FRAGMENTS",       "value": str(len(ev.emails))},
            {"key": "GIT REPOS ANALYZED",    "value": str(ev.repos_found)},
            {"key": "DOCUMENTS SAMPLED",     "value": str(len(ev.docs))},
            {"key": "CONTACTS IDENTIFIED",   "value": str(contact_count)},
            {"key": "SSH HOSTS MAPPED",      "value": str(len(ev.ssh_hosts))},
            {"key": "CREDENTIAL VAULTS",     "value": str(len(ev.password_managers))},
            {"key": "BEHAVIORAL MODEL",      "value": "COMPLETE"},
            {"key": "PREDICTION ACCURACY",   "value": f"{accuracy}%"},
            {"key": "PSYCHOLOGICAL PROFILE", "value": "MAPPED"},
            {"key": "DOMINANT CATEGORY",     "value": ev.dominant_category.upper()},
            {"key": "RISK ASSESSMENT",       "value": "LOW THREAT"},
            {"key": "STATUS",                "value": "FULLY COMPROMISED"},
        ]

        sample_artifacts: list[dict[str, str]] = []
        for cat, bag in [
            ("Browser",  ev.browser),
            ("Email",    ev.emails),
            ("Git",      ev.git_commits),
            ("Document", ev.docs),
            ("SSH",      ev.ssh_hosts),
        ]:
            if bag:
                sample_artifacts.append({"category": cat, "value": bag[0]})

        return {
            "session_id":     session_id,
            "profile_lines":  profile_lines,
            "sample_artifacts": sample_artifacts,
            "data_richness":  ev.data_richness,
            "dominant_category": ev.dominant_category,
            "total_artifacts": (
                len(ev.browser) + len(ev.emails) + len(ev.git_commits)
                + len(ev.docs) + len(ev.ssh_hosts)
            ),
            "built_at": time.time(),
        }

    @staticmethod
    def _empty_profile(session_id: str) -> dict[str, Any]:
        return {
            "session_id": session_id,
            "profile_lines": [
                {"key": "SUBJECT",  "value": "UNKNOWN@UNKNOWN"},
                {"key": "STATUS",   "value": "INSUFFICIENT DATA — PREDICTION ABORTED"},
            ],
            "sample_artifacts": [],
            "data_richness": 0.0,
            "dominant_category": "None",
            "total_artifacts": 0,
            "built_at": time.time(),
        }

    def reset_session(self, session_id: str) -> None:
        self._sessions.pop(session_id, None)
