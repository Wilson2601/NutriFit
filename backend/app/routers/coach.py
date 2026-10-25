from fastapi import APIRouter, Depends, HTTPException, Query
from datetime import date, datetime, timezone, timedelta

from app.firebase import db
from app.auth import require_role
from app.schemas import PrescriptionRequest, AddClientRequest
from app.notifications import send_push_notification
from app.routers.missions import evaluate_mission
from app import nutrition
from app.timeutil import today_str, days_ago_str

router = APIRouter(prefix="/coach", tags=["coach"], dependencies=[Depends(require_role("coach"))])


def _client_target(client_id: str) -> dict:
    return nutrition.get_target(client_id)


def _status_for(report: dict) -> dict:
    """Coach-facing status from the shared adherence rules (last 7 completed days), not from a separate protein rule."""
    if report["loggedDays"] == 0:
        return {"key": "no_data", "label": "No records", "icon": "➖"}
    rate = report["adherenceRate"]
    if rate >= 70:
        return {"key": "on_track", "label": "On track", "icon": "✅"}
    if rate >= 40:
        return {"key": "low", "label": "Low", "icon": "⚠️"}
    return {"key": "off_track", "label": "Off track", "icon": "❌"}


def _client_summary(client_snap) -> dict:
    client = client_snap.to_dict()
    today = nutrition.daily_summary(client_snap.id, with_meals=False)
    report = nutrition.adherence_report(client_snap.id, 7)
    status = _status_for(report)
    return {
        "id": client_snap.id,
        "name": client["name"],
        "initials": client.get("avatarInitials"), "avatarB64": client.get("avatarB64"),
        "goal": client.get("goal"),
        "weightKg": client.get("weightKg"),
        "protein": today["consumed"]["protein"], "proteinTarget": today["target"]["protein"],
        "carbs": today["consumed"]["carbs"], "carbsTarget": today["target"]["carbs"],
        "adherenceRate": report["adherenceRate"], "loggingCompleteness": report["loggingCompleteness"],
        "status": status["key"], "statusLabel": status["label"], "statusIcon": status["icon"],
    }


def _my_clients(coach_uid: str):
    return [
        snap for snap in db.collection("users").stream()
        if snap.to_dict().get("role") == "user" and snap.to_dict().get("coachId") == coach_uid
    ]


@router.get("/dashboard")
def dashboard(coach: dict = Depends(require_role("coach"))):
    clients = [_client_summary(s) for s in _my_clients(coach["uid"])]
    on_track = sum(1 for c in clients if c["status"] == "on_track")
    review = len(clients) - on_track
    needing_attention = sorted(
        [c for c in clients if c["status"] != "on_track"],
        key=lambda c: c["adherenceRate"],
    )[:5]
    filler = [c for c in clients if c["status"] == "on_track"][: max(0, 3 - len(needing_attention))]

    return {
        "coach": {"id": coach["uid"], "name": coach["name"], "initials": coach.get("avatarInitials"), "avatarB64": coach.get("avatarB64")},
        "stats": {"clients": len(clients), "on_track": on_track, "review": review},
        "clients_needing_attention": (needing_attention + filler)[:3],
    }


@router.get("/clients")
def list_clients(status: str = None, search: str = None, coach: dict = Depends(require_role("coach"))):
    clients = [_client_summary(s) for s in _my_clients(coach["uid"])]
    if status and status != "All":
        if status == "Review":
            clients = [c for c in clients if c["status"] != "on_track"]
        elif status == "On Track":
            clients = [c for c in clients if c["status"] == "on_track"]
    if search:
        clients = [c for c in clients if search.lower() in c["name"].lower()]
    clients.sort(key=lambda c: c["name"])
    return {"clients": clients}


@router.post("/clients", status_code=201)
def add_client(payload: AddClientRequest, coach: dict = Depends(require_role("coach"))):
    matches = list(db.collection("users").where("email", "==", payload.email).stream())
    matches = [m for m in matches if m.to_dict().get("role") == "user"]
    if not matches:
        raise HTTPException(status_code=404, detail="No user account found with that email. They need to register as a user first.")
    client_snap = matches[0]
    if client_snap.to_dict().get("coachId") == coach["uid"]:
        raise HTTPException(status_code=409, detail="This client is already in your roster")

    db.collection("users").document(client_snap.id).update({"coachId": coach["uid"]})
    return {"client": _client_summary(db.collection("users").document(client_snap.id).get())}


def _require_own_client(coach_uid: str, client_id: str):
    snap = db.collection("users").document(client_id).get()
    if not snap.exists or snap.to_dict().get("coachId") != coach_uid:
        raise HTTPException(status_code=404, detail="Client not found in your roster")
    return snap


@router.get("/clients/{client_id}")
def client_detail(client_id: str, coach: dict = Depends(require_role("coach"))):
    snap = _require_own_client(coach["uid"], client_id)
    summary = _client_summary(snap)
    summary["email"] = snap.to_dict().get("email")
    summary["target"] = _client_target(client_id)
    return {"client": summary}


@router.put("/clients/{client_id}/targets")
def set_targets(client_id: str, payload: PrescriptionRequest, coach: dict = Depends(require_role("coach"))):
    _require_own_client(coach["uid"], client_id)
    for label, value, lo, hi, unit in (
        ("Calories", payload.calories, 500, 8000, "kcal"), ("Protein", payload.proteinG, 10, 500, "g"),
        ("Carbs", payload.carbsG, 10, 1000, "g"), ("Fat", payload.fatG, 5, 400, "g"),
    ):
        if not lo <= value <= hi:
            raise HTTPException(status_code=422, detail=f"{label} must be between {lo} and {hi} {unit}. Please check the number.")
    db.collection("prescriptions").add({
        "clientId": client_id, "coachId": coach["uid"],
        "proteinG": payload.proteinG, "carbsG": payload.carbsG,
        "fatG": payload.fatG, "calories": payload.calories,
        "createdAt": datetime.now(timezone.utc).isoformat(),
    })
    send_push_notification(
        client_id,
        "🎯 New targets from your coach",
        f"Your macro plan was updated — {round(payload.calories)} kcal/day. New recipes will be optimised to match.",
        data={"type": "targets_updated"},
    )
    return {"ok": True, "target": _client_target(client_id)}


@router.get("/clients/{client_id}/progress")
def client_progress(client_id: str, days: int = Query(7, ge=1, le=90), coach: dict = Depends(require_role("coach"))):
    snap = _require_own_client(coach["uid"], client_id)
    client = snap.to_dict()
    target = _client_target(client_id)

    report = nutrition.adherence_report(client_id, days)
    logged = [h for h in report["history"] if h["hasRecords"]]
    avg = lambda key: round(sum(h["consumed"][key] for h in logged) / len(logged)) if logged else 0
    avg_pct = lambda key: round(sum(h["components"][key]["percent"] or 0 for h in logged) / len(logged)) if logged else 0

    avg_protein = avg("protein")
    status = _status_for(report)
    today = nutrition.daily_summary(client_id)
    return {
        "client": {
            "id": client_id, "name": client["name"], "initials": client.get("avatarInitials"), "avatarB64": client.get("avatarB64"),
            "goal": client.get("goal"), "weightKg": client.get("weightKg"), "goalWeightKg": client.get("goalWeightKg"),
        },
        "status": status["label"], "statusKey": status["key"],
        "daysAdhered": report["adherentDays"], "daysTracked": report["observationDays"],
        "avgCompliance": avg_pct("calories"), "avgProtein": avg_protein,
        "streakDays": client.get("streakDays", 0),
        "adherence": {k: report[k] for k in (
            "days", "startDate", "endDate", "observationDays", "loggedDays", "noRecordDays", "adherentDays",
            "adherenceRate", "adherenceRateOfLoggedDays", "loggingCompleteness", "config")},
        "today": {k: today[k] for k in ("date", "hasRecords", "target", "consumed", "remaining", "components", "adherent", "status")},
        "history": report["history"],
        "macroAdherence": {
            "protein": {"value": avg_protein, "target": target["proteinG"], "pct": avg_pct("protein")},
            "carbs": {"value": avg("carbs"), "target": target["carbsG"], "pct": avg_pct("carbs")},
            "fat": {"value": avg("fat"), "target": target["fatG"], "pct": avg_pct("fat")},
            "calories": {"value": avg("calories"), "target": target["calories"], "pct": avg_pct("calories")},
        },
        "todayMission": {k: v for k, v in evaluate_mission(client_id).items() if k in ("passed", "criteria", "date")},
    }
