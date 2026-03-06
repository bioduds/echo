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

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(name)s] %(levelname)s: %(message)s",
)
logger = logging.getLogger("echo.main")

analyzer = PatternAnalyzer()
brain = EchoBrain()

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
    return {"status": "ok", "service": "echo-ai", "version": "2.0", "timestamp": time.time()}


@app.post("/session/new")
async def new_session():
    session_id = str(uuid.uuid4())[:8]
    analyzer.create_session(session_id)
    brain.reset_session()
    logger.info("New session: %s", session_id)
    return {"session_id": session_id}


@app.post("/system_context")
async def system_context(req: SystemContextRequest):
    brain.set_system_context(req.context)
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
    action = brain.decide(prediction, req.round, game_state=state)
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
