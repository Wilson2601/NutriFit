from fastapi import APIRouter, HTTPException, Depends
import bcrypt
from datetime import datetime, timezone

from app.firebase import db, create_firebase_user, delete_firebase_user, is_using_real_firebase, DEV_MODE
from app.schemas import RegisterRequest, LoginRequest, ProfileUpdateRequest, NotificationPrefsRequest, AvatarRequest
from app.avatar import process_avatar
from app.photo_check import PhotoError
from app.auth import get_current_user

router = APIRouter(prefix="/auth", tags=["auth"])


def _initials(name: str) -> str:
    parts = name.strip().split()
    return "".join(p[0] for p in parts[:2]).upper() if parts else "?"


@router.post("/register", status_code=201)
def register(payload: RegisterRequest):
    if payload.role not in ("user", "coach"):
        raise HTTPException(status_code=400, detail="role must be 'user' or 'coach'")

    existing = list(db.collection("users").where("email", "==", payload.email).stream())
    if existing:
        raise HTTPException(status_code=409, detail="An account with this email already exists")

    # Creates the real Firebase Auth user in production, or a synthetic dev uid in fake mode.
    uid = create_firebase_user(payload.email, payload.password, payload.name)

    profile = {
        "role": payload.role,
        "name": payload.name,
        "email": payload.email,
        "phone": payload.phone,
        "goal": payload.goal or "maintain",
        "weightKg": payload.weightKg or 70,
        "goalWeightKg": payload.goalWeightKg or (payload.weightKg or 70),
        "streakDays": 0,
        "avatarInitials": _initials(payload.name),
        "coachId": None,
        "createdAt": datetime.now(timezone.utc).isoformat(),
    }
    if not is_using_real_firebase():
        # Only needed so our own /auth/login (dev-mode only) can check credentials —
        # real deployments never store this; Firebase Auth manages passwords itself.
        profile["_devPasswordHash"] = bcrypt.hashpw(payload.password.encode(), bcrypt.gensalt()).decode()

    db.collection("users").document(uid).set(profile)

    if payload.role == "user":
        db.collection("prescriptions").add({
            "clientId": uid, "coachId": None,
            "proteinG": 150, "carbsG": 200, "fatG": 60, "calories": 2000,
            "createdAt": datetime.now(timezone.utc).isoformat(),
        })
        _seed_default_reminders(uid)

    clean_profile = {k: v for k, v in profile.items() if not k.startswith("_")}
    return {"uid": uid, "user": {**clean_profile, "uid": uid}, "devToken": f"fakeuid:{uid}" if not is_using_real_firebase() else None}


@router.post("/login")
def dev_login(payload: LoginRequest):
    """
    Dev-mode only. In production the Flutter app authenticates directly against
    Firebase Auth and never calls this — it's here purely so the backend can be
    developed and tested locally before a real Firebase project is wired up.
    """
    if is_using_real_firebase():
        raise HTTPException(
            status_code=400,
            detail="Real Firebase is configured — sign in with the Firebase Auth SDK on the client instead of this endpoint.",
        )
    matches = list(db.collection("users").where("email", "==", payload.email).stream())
    if not matches:
        raise HTTPException(status_code=401, detail="Invalid email or password")
    snap = matches[0]
    profile = snap.to_dict()
    if not bcrypt.checkpw(payload.password.encode(), profile.get("_devPasswordHash", "").encode()):
        raise HTTPException(status_code=401, detail="Invalid email or password")
    if payload.role and profile.get("role") != payload.role:
        raise HTTPException(status_code=401, detail=f"This account is registered as a {profile.get('role')}, not a {payload.role}")

    clean_profile = {k: v for k, v in profile.items() if not k.startswith("_")}
    return {"token": f"fakeuid:{snap.id}", "user": {**clean_profile, "uid": snap.id}}


@router.get("/me")
def me(user: dict = Depends(get_current_user)):
    return {"user": _public(user)}


@router.patch("/fcm-token")
def save_fcm_token(payload: dict, user: dict = Depends(get_current_user)):
    """Registers this device's FCM token so the backend can push notifications to it."""
    token = payload.get("token")
    if not token:
        raise HTTPException(status_code=400, detail="token is required")
    db.collection("users").document(user["uid"]).update({"fcmToken": token})
    return {"ok": True}


def _seed_default_reminders(uid: str):
    defaults = [
        ("Defrost Reminder", "6:00 AM", "Defrost proteins for the day", "❄️", True),
        ("Pre-Workout Meal", "11:30 AM", "Carb timing window", "⚡", True),
        ("Post-Workout Protein", "2:00 PM", "Within 30 min of training", "💪", False),
        ("Evening Meal Prep", "5:30 PM", "Check grocery list", "🛒", True),
        ("Hydration Check", "Every 2 hrs", "Water intake reminder", "💧", False),
        ("Evening Review", "8:00 PM", "Review tomorrow's plan", "🌙", True),
    ]
    reminders_col = db.collection("users").document(uid).collection("reminders")
    for i, (title, time_label, subtitle, icon, enabled) in enumerate(defaults):
        reminders_col.add({
            "title": title, "timeLabel": time_label, "subtitle": subtitle,
            "icon": icon, "enabled": enabled, "sortOrder": i,
        })


VALID_GOALS = ("muscle_gain", "weight_loss", "maintain", "performance")
DEFAULT_PREFS = {"push": True, "targets": True, "notes": True, "chat": True, "mission": True}
USER_SUBCOLLECTIONS = ("reminders", "groceryItems", "mealLogs", "mealPhotos", "messages", "coachNotes")


def _public(profile: dict) -> dict:
    """Never send internal/secret fields (anything starting with '_', and the push token) to the client."""
    return {k: v for k, v in profile.items() if not k.startswith("_") and k != "fcmToken"}


@router.patch("/profile")
def update_profile(payload: ProfileUpdateRequest, user: dict = Depends(get_current_user)):
    changes = {}
    if payload.name is not None:
        name = payload.name.strip()
        if not name:
            raise HTTPException(status_code=422, detail="Name cannot be empty")
        changes["name"] = name
        changes["avatarInitials"] = _initials(name)
    if payload.phone is not None:
        changes["phone"] = payload.phone.strip()
    if payload.goal is not None:
        if payload.goal not in VALID_GOALS:
            raise HTTPException(status_code=422, detail=f"goal must be one of {', '.join(VALID_GOALS)}")
        changes["goal"] = payload.goal
    for field in ("weightKg", "goalWeightKg"):
        value = getattr(payload, field)
        if value is not None:
            if not 20 <= value <= 400:
                raise HTTPException(status_code=422, detail=f"{field} must be between 20 and 400")
            changes[field] = value
    if changes:
        db.collection("users").document(user["uid"]).update(changes)
    fresh = db.collection("users").document(user["uid"]).get().to_dict()
    fresh["uid"] = user["uid"]
    return {"user": _public(fresh)}


@router.put("/avatar")
def upload_avatar(payload: AvatarRequest, user: dict = Depends(get_current_user)):
    try:
        b64 = process_avatar(payload.imageBase64)
    except PhotoError as e:
        raise HTTPException(status_code=422, detail=str(e))
    db.collection("users").document(user["uid"]).update({"avatarB64": b64})
    fresh = db.collection("users").document(user["uid"]).get().to_dict()
    fresh["uid"] = user["uid"]
    return {"user": _public(fresh)}


@router.delete("/avatar")
def remove_avatar(user: dict = Depends(get_current_user)):
    db.collection("users").document(user["uid"]).update({"avatarB64": None})
    fresh = db.collection("users").document(user["uid"]).get().to_dict()
    fresh["uid"] = user["uid"]
    return {"user": _public(fresh)}


@router.get("/preferences")
def get_preferences(user: dict = Depends(get_current_user)):
    return {"preferences": {**DEFAULT_PREFS, **user.get("notifPrefs", {})}}


@router.patch("/preferences")
def update_preferences(payload: NotificationPrefsRequest, user: dict = Depends(get_current_user)):
    prefs = {**DEFAULT_PREFS, **user.get("notifPrefs", {})}
    prefs.update({k: v for k, v in payload.model_dump().items() if v is not None})
    db.collection("users").document(user["uid"]).update({"notifPrefs": prefs})
    return {"preferences": prefs}


@router.get("/my-coach")
def my_coach(user: dict = Depends(get_current_user)):
    coach_id = user.get("coachId")
    if not coach_id:
        return {"coach": None}
    snap = db.collection("users").document(coach_id).get()
    if not snap.exists:
        return {"coach": None}
    c = snap.to_dict()
    return {"coach": {"id": coach_id, "name": c.get("name"), "email": c.get("email"), "initials": c.get("avatarInitials"), "avatarB64": c.get("avatarB64")}}


@router.delete("/me")
def delete_account(user: dict = Depends(get_current_user)):
    """Permanently deletes the caller's account and all of their data."""
    uid = user["uid"]
    user_ref = db.collection("users").document(uid)

    for sub in USER_SUBCOLLECTIONS:
        for snap in user_ref.collection(sub).stream():
            user_ref.collection(sub).document(snap.id).delete()
    for snap in db.collection("prescriptions").where("clientId", "==", uid).stream():
        db.collection("prescriptions").document(snap.id).delete()

    if user.get("role") == "coach":  # release this coach's clients
        for snap in db.collection("users").stream():
            if snap.to_dict().get("coachId") == uid:
                db.collection("users").document(snap.id).update({"coachId": None})

    user_ref.delete()
    delete_firebase_user(uid)
    return {"ok": True}
