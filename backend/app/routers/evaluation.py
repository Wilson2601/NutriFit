"""Records real evaluation responses (SUS, satisfaction, task results) and summarises them for the coach/researcher."""
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel

from app import evaluation
from app.auth import get_current_user, require_role
from app.firebase import db
from app.timeutil import now_local

router = APIRouter(prefix="/evaluation", tags=["evaluation"])


class Answers(BaseModel):
    participantId: str
    responses: List[int]


class TaskResult(BaseModel):
    participantId: str
    taskId: str
    success: bool
    seconds: Optional[float] = None
    notes: Optional[str] = None


def _store(kind, payload: dict, user):
    db.collection("evaluations").add({"kind": kind, "recordedBy": user["uid"], "recordedAt": now_local().isoformat(), **payload})


@router.get("/instruments")
def instruments(user: dict = Depends(get_current_user)):
    return {"sus": evaluation.SUS_ITEMS, "satisfaction": evaluation.SATISFACTION_ITEMS,
            "tasks": [{"id": i, "text": t} for i, t in evaluation.TASKS]}


@router.post("/sus", status_code=201)
def submit_sus(p: Answers, user: dict = Depends(get_current_user)):
    try:
        score = evaluation.sus_score(p.responses)
    except evaluation.EvaluationError as e:
        raise HTTPException(status_code=422, detail=str(e))
    _store("sus", {"participantId": p.participantId, "responses": p.responses, "score": score}, user)
    return {"score": score, "grade": evaluation.sus_grade(score)}


@router.post("/satisfaction", status_code=201)
def submit_satisfaction(p: Answers, user: dict = Depends(get_current_user)):
    try:
        result = evaluation.satisfaction_score(p.responses)
    except evaluation.EvaluationError as e:
        raise HTTPException(status_code=422, detail=str(e))
    _store("satisfaction", {"participantId": p.participantId, "responses": p.responses, **result}, user)
    return result


@router.post("/task", status_code=201)
def submit_task(p: TaskResult, user: dict = Depends(get_current_user)):
    if p.taskId not in {t[0] for t in evaluation.TASKS}:
        raise HTTPException(status_code=422, detail="Unknown task id")
    _store("task", p.model_dump(), user)
    return {"ok": True}


@router.get("/summary")
def summary(coach: dict = Depends(require_role("coach"))):
    rows = [s.to_dict() for s in db.collection("evaluations").stream()]
    pick = lambda kind: [r for r in rows if r["kind"] == kind]
    return evaluation.summarize([r["responses"] for r in pick("sus")], [r["responses"] for r in pick("satisfaction")], pick("task"))
