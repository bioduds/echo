"""
ECHO — Game AI Backend.

Receives player actions, predicts behavior with OLMo 2,
and generates the Echo mirror's counter-strategy.
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

app = FastAPI(title="ECHO Game AI", version="1.0.0")

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


@app.get("/health")
async def health():
    return {"status": "ok", "service": "echo-ai", "timestamp": time.time()}


@app.post("/session/new")
async def new_session():
    session_id = str(uuid.uuid4())[:8]
    analyzer.create_session(session_id)
    logger.info("New session: %s", session_id)
    return {"session_id": session_id}


@app.post("/action")
async def report_action(report: ActionReport):
    analyzer.record_action(report.session_id, report.model_dump())
    return {"status": "recorded"}


@app.post("/predict")
async def predict(req: PredictRequest):
    dx = req.player_pos[0] - req.echo_pos[0]
    dy = req.player_pos[1] - req.echo_pos[1]
    distance = (dx ** 2 + dy ** 2) ** 0.5

    state = req.model_dump()
    state["distance"] = distance

    prediction = await analyzer.predict_player(req.session_id, state)
    action = brain.decide(prediction, req.round)
    return action


@app.post("/analyze")
async def analyze(req: AnalyzeRequest):
    result = await analyzer.generate_profile(req.session_id, req.round)
    logger.info(
        "Analysis for session %s round %d: %s",
        req.session_id, req.round, result.get("playstyle", "?"),
    )
    return result
