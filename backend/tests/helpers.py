import uuid
from datetime import datetime, timedelta, timezone

from app.firebase import db
from app.timeutil import days_ago_str


def new_user(role="user", coach_id=None, target=None, target_days_ago=0):
    """Creates an isolated user (and optional coach prescription) in the fake Firestore. Returns (uid, headers)."""
    uid = "t_" + uuid.uuid4().hex[:10]
    db.collection("users").document(uid).set({
        "role": role, "name": "Test " + uid, "email": f"{uid}@test.example", "coachId": coach_id, "avatarInitials": "TU",
    })
    if target:
        add_target(uid, target, target_days_ago)
    return uid, {"Authorization": f"Bearer fakeuid:{uid}"}


def add_target(uid, target, days_ago=0):
    created = datetime.now(timezone.utc) - timedelta(days=days_ago)
    db.collection("prescriptions").add({"clientId": uid, "coachId": "c", **target, "createdAt": created.isoformat()})


def add_log(uid, day_offset, calories, protein, carbs, fat, status="consumed"):
    db.collection("users").document(uid).collection("mealLogs").add({
        "recipeName": "Test meal", "mealType": "Lunch", "logDate": days_ago_str(day_offset), "status": status,
        "loggedAt": datetime.now(timezone.utc).isoformat(),
        "calories": calories, "protein": protein, "carbs": carbs, "fat": fat,
    })


TARGET = {"calories": 2000, "proteinG": 150, "carbsG": 200, "fatG": 60}
