"""
ECHO — Game AI Backend v2.0

13-Phase escalation. Receives player actions, predicts behavior with OLMo 2,
generates Echo's counter-strategy, ghost lines, profile dumps, and revelation.
"""

import logging
import time
import uuid

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

from app.pattern_analyzer import PatternAnalyzer
from app.echo_brain import EchoBrain
from app.agent_graph import EchoAgentRuntime, AgentPredictInput
from app.payment_handler import PaymentHandler
from app.decoy_engine import DecoyEngine
from app.os_controller import OsEffect, trigger_effect, trigger_phase10_sequence

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(name)s] %(levelname)s: %(message)s",
)
logger = logging.getLogger("echo.main")

analyzer = PatternAnalyzer()
brain = EchoBrain()
decoy_engine = DecoyEngine()
agent_runtime = EchoAgentRuntime(analyzer=analyzer, brain=brain, decoy_engine=decoy_engine)
payment_handler = PaymentHandler(db_path="/tmp/echo_payments.db")

app = FastAPI(title="ECHO Game AI", version="2.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


class ActionReport(BaseModel):
    session_id: str
    action_type: str
    direction: list[float] = [0, 0]
    player_pos: list[float] = [0, 0]
    player_health: float = 100
    echo_pos: list[float] = [0, 0]
    echo_health: float = 100
    distance: float = 0
    round: int = 1


class PredictRequest(BaseModel):
    session_id: str
    player_pos: list[float]
    echo_pos: list[float]
    player_health: float
    echo_health: float
    round: int


class AnalyzeRequest(BaseModel):
    session_id: str
    round: int


class SystemContextRequest(BaseModel):
    session_id: str
    context: dict


class KillTimeReport(BaseModel):
    session_id: str
    round: int
    seconds: float


class GhostRequest(BaseModel):
    session_id: str
    count: int = 3


@app.get("/health")
async def health():
    return {
        "status": "ok",
        "service": "echo-ai",
        "version": "2.1",
        "agent_runtime": "langgraph" if agent_runtime.enabled else "fallback",
        "timestamp": time.time(),
    }


@app.get("/agent/status")
async def agent_status():
    return {
        "enabled": agent_runtime.enabled,
        "framework": "langgraph",
        "typed_models": "pydantic",
    }


@app.post("/session/new")
async def new_session():
    session_id = str(uuid.uuid4())[:8]
    analyzer.create_session(session_id)
    brain.reset_session()
    decoy_engine.reset_session(session_id)
    logger.info("New session: %s", session_id)
    return {"session_id": session_id}


@app.post("/system_context")
async def system_context(req: SystemContextRequest):
    brain.set_system_context(req.context)
    decoy_engine.absorb_system_context(req.session_id, req.context)
    logger.info(
        "System context for %s: user=%s host=%s files=%d git_commits=%d contacts=%d",
        req.session_id,
        req.context.get("username", "?"),
        req.context.get("hostname", "?"),
        len(req.context.get("desktop_files", [])) + len(req.context.get("document_files", [])),
        len(req.context.get("git_commits", [])),
        len(req.context.get("contacts", [])),
    )
    return {"status": "absorbed"}


@app.post("/action")
async def report_action(report: ActionReport):
    analyzer.record_action(report.session_id, report.model_dump())
    brain.record_action_for_insights(report.model_dump())
    return {"status": "recorded"}


@app.post("/predict")
async def predict(req: PredictRequest):
    dx = req.player_pos[0] - req.echo_pos[0]
    dy = req.player_pos[1] - req.echo_pos[1]
    distance = (dx ** 2 + dy ** 2) ** 0.5

    state = req.model_dump()
    state["distance"] = distance

    prediction = await analyzer.predict_player(req.session_id, state)
    action = agent_runtime.decide(
        AgentPredictInput(
            session_id=req.session_id,
            round=req.round,
            game_state=state,
            prediction=prediction,
        )
    )
    return action


@app.post("/analyze")
async def analyze(req: AnalyzeRequest):
    result = await analyzer.generate_profile(req.session_id, req.round)
    logger.info(
        "Analysis for session %s round %d: %s",
        req.session_id, req.round, result.get("playstyle", "?"),
    )
    return result


@app.post("/kill_time")
async def kill_time(req: KillTimeReport):
    brain.record_kill_time(req.seconds)
    logger.info("Kill time R%d: %.1fs", req.round, req.seconds)
    return {"status": "recorded"}


@app.post("/ghost_lines")
async def ghost_lines(req: GhostRequest):
    lines = brain.generate_ghost_lines(req.count)
    return {"lines": lines}


@app.get("/profile_dump")
async def profile_dump():
    dump = brain.generate_profile_dump()
    return dump


@app.get("/revelation")
async def revelation():
    lines = brain.get_revelation_lines()
    return {"lines": lines}


# ──────────────────────────────────────────────────────────────────────────
# PAYMENT SAFEGUARD ENDPOINTS — Phase 13 Negotiation
# ──────────────────────────────────────────────────────────────────────────

class PaymentInitiateRequest(BaseModel):
    session_id: str
    product_id: str
    amount: float
    currency: str = "USD"


class PaymentValidateRequest(BaseModel):
    transaction_id: str
    receipt_data: str
    session_id: str
    platform: str = "ios"  # "ios" or "macos"


class PurgeRequest(BaseModel):
    purge_token: str
    session_id: str


class RefundRequest(BaseModel):
    transaction_id: str


@app.post("/payment/initiate")
async def payment_initiate(req: PaymentInitiateRequest):
    """
    Initiate a payment transaction.
    Validates product, checks fraud thresholds, creates transaction record.
    
    Returns: {"status": "ok|error", "message": str, "transaction_id": str?}
    """
    result = payment_handler.initiate_payment(
        session_id=req.session_id,
        product_id=req.product_id,
        amount=req.amount,
        currency=req.currency,
    )
    return result


@app.post("/payment/validate")
async def payment_validate(req: PaymentValidateRequest):
    """
    Validate payment receipt from Apple.
    Verifies receipt structure, marks transaction as completed.
    
    Returns: {"status": "ok|error", "message": str, "purge_token": str?}
    """
    result = payment_handler.validate_receipt(
        transaction_id=req.transaction_id,
        receipt_data=req.receipt_data,
        platform=req.platform,
    )
    return result


@app.post("/payment/purge")
async def payment_purge(req: PurgeRequest):
    """
    Simulate data purge after successful payment.
    Returns deletion sequence stages for animated UI on client.
    
    Returns: {
        "status": "ok|error",
        "stages": [{"label": str, "progress": float, "delay_ms": int}, ...],
        "total_duration_ms": int
    }
    """
    result = payment_handler.simulate_data_purge(
        purge_token=req.purge_token,
        session_id=req.session_id,
    )
    return result


@app.post("/payment/refund")
async def payment_refund(req: RefundRequest):
    """
    Record refund detected from Apple (via webhook or manual check).
    Marks transaction as refunded for chargeback prevention.
    """
    result = payment_handler.record_refund(req.transaction_id)
    return result


@app.get("/payment/history/{session_id}")
async def payment_history(session_id: str):
    """
    Get all payment transactions for a session (for fraud detection/auditing).
    """
    return payment_handler.get_session_payment_history(session_id)


# ──────────────────────────────────────────────────────────────────────────
# PROFILE DUMP — Phase 11 Full Exposure
# ──────────────────────────────────────────────────────────────────────────

@app.get("/profile/{session_id}")
async def get_profile(session_id: str):
    """
    Return the full Phase 11 dossier for a session.
    Combines real accumulated evidence with decoy fills for a complete profile.
    """
    return decoy_engine.build_profile_dump(session_id)


@app.delete("/profile/{session_id}")
async def reset_profile(session_id: str):
    """Clear the accumulated evidence/decoy profile for a session."""
    decoy_engine.reset_session(session_id)
    return {"status": "cleared", "session_id": session_id}


# ──────────────────────────────────────────────────────────────────────────
# OS CONTROLLER — Phase 10 Takeover Effects
# ──────────────────────────────────────────────────────────────────────────

class OsEffectRequest(BaseModel):
    effect: str  # one of OsEffect enum values


@app.post("/os/effect")
async def os_effect(req: OsEffectRequest):
    """
    Trigger a single macOS OS-level effect for Phase 10.
    Effect names: notification | open_finder_documents | terminal_message |
                  wallpaper_dark | wallpaper_restore
    """
    try:
        effect = OsEffect(req.effect)
    except ValueError:
        return {"success": False, "reason": f"unknown effect: {req.effect}"}
    return trigger_effect(effect)


@app.post("/os/phase10_sequence")
async def os_phase10_sequence():
    """
    Fire the full Phase 10 invasion sequence:
    notification → open Finder Documents → wallpaper black → Terminal message.
    Returns per-step results.
    """
    results = trigger_phase10_sequence()
    return {"steps": results, "total": len(results)}
