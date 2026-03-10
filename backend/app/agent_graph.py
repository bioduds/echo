"""LangGraph runtime for ECHO combat decisions.

This module provides an explicit phase-aware plan -> execute -> decide pipeline.
All API-facing data is validated through Pydantic models.
"""

from __future__ import annotations

from typing import Any

from pydantic import BaseModel, Field

from app.echo_brain import EchoBrain
from app.pattern_analyzer import PatternAnalyzer

try:
    from app.decoy_engine import DecoyEngine
except Exception:
    DecoyEngine = None  # type: ignore[misc,assignment]

try:
    from langgraph.graph import END, START, StateGraph

    LANGGRAPH_AVAILABLE = True
except Exception:
    LANGGRAPH_AVAILABLE = False
    END = "END"
    START = "START"
    StateGraph = None


class AgentPredictInput(BaseModel):
    session_id: str
    round: int = Field(ge=1)
    game_state: dict[str, Any]
    prediction: dict[str, Any]


class AgentRevealItem(BaseModel):
    label: str
    value: str


class AgentToolIntent(BaseModel):
    name: str
    reason: str


class AgentPhasePlan(BaseModel):
    phase: int
    mode: str
    intents: list[AgentToolIntent]


class AgentDecision(BaseModel):
    action: str
    direction: list[float]
    accuracy: float = 0.0
    round: int
    phase: int
    speed_mult: float = 1.0
    damage_mult: float = 1.0
    health_mult: float = 1.0
    dodge_skill: float = 0.0
    aim_skill: float = 0.0
    taunt: str | None = None
    no_combat: bool = False
    echo_stops_dodging: bool = False
    echo_regens: bool = False
    threat_level: str = "low"
    reveal_items: list[AgentRevealItem] = Field(default_factory=list)
    agent_plan: AgentPhasePlan


class EchoAgentRuntime:
    def __init__(self, analyzer: PatternAnalyzer, brain: EchoBrain, decoy_engine: Any = None):
        self.analyzer = analyzer
        self.brain = brain
        self.decoy_engine = decoy_engine  # DecoyEngine | None
        self._graph = self._build_graph() if LANGGRAPH_AVAILABLE else None

    @property
    def enabled(self) -> bool:
        return self._graph is not None

    def _build_graph(self):
        graph = StateGraph(dict)
        graph.add_node("plan_phase", self._node_plan_phase)
        graph.add_node("execute_intents", self._node_execute_intents)
        graph.add_node("decide_combat", self._node_decide_combat)
        graph.add_node("finalize", self._node_finalize)

        graph.add_edge(START, "plan_phase")
        graph.add_edge("plan_phase", "execute_intents")
        graph.add_edge("execute_intents", "decide_combat")
        graph.add_edge("decide_combat", "finalize")
        graph.add_edge("finalize", END)

        return graph.compile()

    def _node_plan_phase(self, state: dict[str, Any]) -> dict[str, Any]:
        req = AgentPredictInput.model_validate(state["request"])
        phase = min(req.round, 13)

        intents: list[AgentToolIntent] = []
        if phase <= 3:
            mode = "observe"
            intents = [
                AgentToolIntent(name="profile_player", reason="Map behavior patterns early."),
            ]
        elif phase <= 6:
            mode = "intrude"
            intents = [
                AgentToolIntent(name="mine_browser", reason="Surface personal browsing artifacts."),
                AgentToolIntent(name="mine_mail", reason="Surface private mail subjects."),
            ]
        elif phase <= 9:
            mode = "pressure"
            intents = [
                AgentToolIntent(name="mine_passwords", reason="Identify credential vault surface."),
                AgentToolIntent(name="crosslink_identity", reason="Correlate behavior with data traces."),
            ]
        else:
            mode = "dominate"
            intents = [
                AgentToolIntent(name="persist_reveals", reason="Keep evidence visible and cumulative."),
                AgentToolIntent(name="hard_taunt", reason="Use cold, direct high-pressure language."),
            ]

        return {
            "request": state["request"],
            "plan": AgentPhasePlan(
                phase=phase,
                mode=mode,
                intents=intents,
            ).model_dump(),
        }

    def _node_execute_intents(self, state: dict[str, Any]) -> dict[str, Any]:
        req = AgentPredictInput.model_validate(state["request"])
        plan = AgentPhasePlan.model_validate(state.get("plan", {}))

        raw_ctx = self.brain._system_ctx if hasattr(self.brain, "_system_ctx") else {}

        # Enrich sparse real context with phase-appropriate decoys
        if self.decoy_engine is not None:
            ctx = self.decoy_engine.enrich_context(req.session_id, req.round, raw_ctx)
        else:
            ctx = raw_ctx

        reveal_items: list[dict[str, str]] = []
        taunt_override: str | None = None

        browser = [str(x) for x in ctx.get("browser_history", []) if str(x).strip()]
        emails = [str(x) for x in ctx.get("email_subjects", []) if str(x).strip()]
        managers = [str(x) for x in ctx.get("password_managers", []) if str(x).strip()]
        commits = [str(x) for x in ctx.get("git_commits", []) if str(x).strip()]
        docs = [str(x) for x in ctx.get("doc_samples", []) if str(x).strip()]
        recent_files = [str(x) for x in ctx.get("recent_files", []) if str(x).strip()]
        contacts = [str(x) for x in ctx.get("contacts", []) if str(x).strip()]
        ssh_hosts = [str(x) for x in ctx.get("ssh_hosts", []) if str(x).strip()]

        pick_idx = max(0, (req.round - 1) % 3)
        reveal_budget = 1 if req.round <= 5 else 2 if req.round <= 9 else 4

        def _append_unique(label: str, values: list[str], limit: int):
            for i in range(min(limit, len(values))):
                value = values[(pick_idx + i) % len(values)]
                item = {"label": label, "value": value}
                if item not in reveal_items:
                    reveal_items.append(item)

        for intent in plan.intents:
            if intent.name == "mine_browser" and browser:
                _append_unique("Browser", browser, reveal_budget)
                value = browser[pick_idx % len(browser)]
                taunt_override = f"I retained this history entry: {value}"

            if intent.name == "mine_mail" and emails:
                _append_unique("Email", emails, reveal_budget)
                value = emails[pick_idx % len(emails)]
                taunt_override = f"I indexed your mail subject line: \"{value}\"."

            if intent.name == "mine_passwords" and managers:
                _append_unique("Password", managers, max(1, reveal_budget - 1))
                value = managers[pick_idx % len(managers)]
                taunt_override = f"Credential vault present: {value}."

            if intent.name == "crosslink_identity" and reveal_items:
                taunt_override = "Your behavior and your machine data align. You are fully predictable here."

            if intent.name == "hard_taunt":
                if reveal_items:
                    taunt_override = "Nothing fades now. Each trace stays visible until you break focus."
                else:
                    taunt_override = "You are not fighting uncertainty anymore. You are fighting disclosure."

            if intent.name == "persist_reveals":
                if browser:
                    reveal_items.append({"label": "Browser", "value": browser[pick_idx % len(browser)]})
                if emails:
                    reveal_items.append({"label": "Email", "value": emails[pick_idx % len(emails)]})
                if managers:
                    reveal_items.append({"label": "Password", "value": managers[pick_idx % len(managers)]})

        # Keep pressure non-zero: fallback to other concrete evidence if sensitive buckets are empty.
        if not reveal_items:
            if recent_files:
                _append_unique("Recent File", recent_files, min(3, reveal_budget))
            if commits:
                _append_unique("Git Commit", commits, min(2, reveal_budget))
            if docs:
                _append_unique("Document", docs, min(2, reveal_budget))
            if contacts:
                _append_unique("Contact", contacts, 1)
            if ssh_hosts:
                _append_unique("SSH Host", ssh_hosts, 1)

        if not taunt_override:
            evidence_count = len(reveal_items)
            if evidence_count > 0:
                top_labels = ", ".join(sorted({i["label"] for i in reveal_items})[:3])
                taunt_override = (
                    f"Evidence indexed: {evidence_count} artifact(s) across {top_labels}. "
                    "Everything displayed is recovered from local traces."
                )
            else:
                taunt_override = "Telemetry remains active. The next artifact is a timing issue, not a possibility."

        # Escalate late-game wording while staying grounded in observable evidence.
        if req.round >= 10 and reveal_items:
            categories = ", ".join(sorted({i["label"] for i in reveal_items})[:3])
            taunt_override = (
                f"Pressure state CRITICAL. {len(reveal_items)} item(s) visible in {categories}. "
                "You are now reacting to confirmed exposure, not speculation."
            )

        if req.round >= 10:
            threat_level = "critical"
        elif reveal_items:
            threat_level = "high"
        else:
            threat_level = "medium"

        return {
            "request": state["request"],
            "plan": plan.model_dump(),
            "reveal_items": reveal_items,
            "threat_level": threat_level,
            "taunt_override": taunt_override,
        }

    def _node_decide_combat(self, state: dict[str, Any]) -> dict[str, Any]:
        req = AgentPredictInput.model_validate(state["request"])
        action = self.brain.decide(req.prediction, req.round, game_state=req.game_state)

        if state.get("taunt_override"):
            action["taunt"] = state["taunt_override"]

        return {
            "request": state["request"],
            "plan": state.get("plan"),
            "reveal_items": state.get("reveal_items", []),
            "threat_level": state.get("threat_level", "low"),
            "action": action,
        }

    def _node_finalize(self, state: dict[str, Any]) -> dict[str, Any]:
        req = AgentPredictInput.model_validate(state["request"])
        action = dict(state.get("action", {}))

        action["threat_level"] = state.get("threat_level", "low")
        action["reveal_items"] = state.get("reveal_items", [])
        action["round"] = req.round
        action["phase"] = min(req.round, 13)
        action["agent_plan"] = state.get("plan") or AgentPhasePlan(
            phase=min(req.round, 13),
            mode="fallback",
            intents=[],
        ).model_dump()

        validated = AgentDecision.model_validate(action)
        return {"decision": validated.model_dump()}

    def decide(self, request: AgentPredictInput) -> dict[str, Any]:
        if self._graph is None:
            fallback = self.brain.decide(
                request.prediction,
                request.round,
                game_state=request.game_state,
            )
            fallback["threat_level"] = "unknown"
            fallback["reveal_items"] = []
            fallback["agent_plan"] = AgentPhasePlan(
                phase=min(request.round, 13),
                mode="fallback",
                intents=[],
            ).model_dump()
            return AgentDecision.model_validate(fallback).model_dump()

        out = self._graph.invoke({"request": request.model_dump()})
        decision = out.get("decision", {})
        return AgentDecision.model_validate(decision).model_dump()
