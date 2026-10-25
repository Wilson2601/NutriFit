"""
Daily mission: prove that today's plan was actually followed.

The mission is PHOTO PROOF plus the same nutrition rules used for adherence (app.nutrition):
  1. photos   - at least one meal is logged and every logged meal has an accepted camera photo
  2. calories - achievement is inside the configured calorie range (default 85%-115%)
  3. protein  - achievement reaches at least the configured protein minimum (default 80%)
Mission completion is NOT the same as nutritional adherence: adherence needs all four nutrients in range
and needs no photos; the mission needs photos but only checks calories and protein.
"""
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException

from app.auth import get_current_user
from app.firebase import db
from app.notifications import send_push_notification
from app import food_vision
from app.photo_check import PhotoError, decode_base64, verify_photo
from app import nutrition
from app.schemas import MealPhotoRequest
from app.timeutil import now_local, today_str

router = APIRouter(prefix="/missions", tags=["missions"])

MAX_CAPTURE_AGE_SECONDS = 10 * 60


def evaluate_mission(uid: str) -> dict:
    """Computes today's mission state for one client from their logs and accepted photos."""
    today = today_str()
    user_ref = db.collection("users").document(uid)
    summary = nutrition.daily_summary(uid, today)
    target = nutrition.get_target(uid, today)

    meals = summary["meals"]
    photo_ids = {
        p.to_dict().get("mealLogId")
        for p in user_ref.collection("mealPhotos").stream()
        if p.to_dict().get("logDate") == today and p.to_dict().get("verified")
    }

    totals = summary["consumed"]
    with_photo = sum(1 for m in meals if m["id"] in photo_ids)
    cal, pro = summary["components"]["calories"], summary["components"]["protein"]
    cal_lo, cal_hi = nutrition.ADHERENCE_RANGES["calories"]
    pro_lo = nutrition.ADHERENCE_RANGES["protein"][0]

    criteria = [
        {
            "key": "photos", "label": "Photo of every meal",
            "met": bool(meals) and with_photo == len(meals),
            "detail": f"{with_photo} of {len(meals)} meals have a camera photo" if meals else "No meals logged yet",
        },
        {
            "key": "calories", "label": "Calories on target",
            "met": cal["percent"] is not None and cal_lo <= cal["percent"] <= cal_hi,
            "detail": f"{round(totals['calories'])} of {round(target['calories'])} kcal ({round(cal['percent'] or 0)}%, goal {round(cal_lo)}-{round(cal_hi)}%)",
        },
        {
            "key": "protein", "label": "Protein goal reached",
            "met": pro["percent"] is not None and pro["percent"] >= pro_lo,
            "detail": f"{round(totals['protein'])} of {round(target['proteinG'])} g ({round(pro['percent'] or 0)}%, goal at least {round(pro_lo)}%)",
        },
    ]
    passed = all(c["met"] for c in criteria)
    return {
        "date": today,
        "passed": passed,
        "criteria": criteria,
        "meals": [
            {
                "id": m["id"], "mealType": m.get("mealType"), "recipeName": m.get("recipeName"),
                "recipeEmoji": m.get("recipeEmoji"), "calories": m.get("calories"),
                "hasPhoto": m["id"] in photo_ids,
            }
            for m in meals
        ],
        "totals": totals,
        "target": target,
    }


@router.get("/today")
def mission_today(user: dict = Depends(get_current_user)):
    if user["role"] != "user":
        raise HTTPException(status_code=403, detail="Requires user role")
    return evaluate_mission(user["uid"])


@router.post("/photo", status_code=201)
def submit_photo(payload: MealPhotoRequest, user: dict = Depends(get_current_user)):
    if user["role"] != "user":
        raise HTTPException(status_code=403, detail="Requires user role")
    uid = user["uid"]

    if payload.source != "camera":
        raise HTTPException(status_code=400, detail="Meal photos must be taken live with the camera.")

    if payload.capturedAt:
        try:
            captured = datetime.fromisoformat(payload.capturedAt.replace("Z", "+00:00"))
            if captured.tzinfo is None:
                captured = captured.replace(tzinfo=timezone.utc)
        except ValueError:
            raise HTTPException(status_code=422, detail="capturedAt must be an ISO-8601 time")
        age = abs((datetime.now(timezone.utc) - captured).total_seconds())
        if age > MAX_CAPTURE_AGE_SECONDS:
            raise HTTPException(status_code=400, detail="That photo is too old. Take a fresh photo now.")

    user_ref = db.collection("users").document(uid)
    log = user_ref.collection("mealLogs").document(payload.mealLogId).get()
    if not log.exists or log.to_dict().get("logDate") != today_str():
        raise HTTPException(status_code=404, detail="Meal not found for today")

    photos_col = user_ref.collection("mealPhotos")
    existing = [{"id": p.id, **p.to_dict()} for p in photos_col.stream()]
    if any(p.get("mealLogId") == payload.mealLogId and p.get("verified") for p in existing):
        raise HTTPException(status_code=409, detail="This meal already has an accepted photo")

    try:
        raw = decode_base64(payload.imageBase64)
        previous = [h for p in existing if p.get("verified") for h in (p.get("sha256"), p.get("ahash")) if h]
        result = verify_photo(raw, previous)
    except PhotoError as e:
        raise HTTPException(status_code=422, detail=str(e))

    before = evaluate_mission(uid)

    reasons = list(result["reasons"])
    if not reasons and food_vision.is_enabled():
        try:
            check = food_vision.check_food_photo(result["thumbnailB64"], log.to_dict().get("recipeName", "your meal"))
        except food_vision.FoodCheckUnavailable:
            raise HTTPException(status_code=503, detail="The food check is temporarily unavailable. Please try again in a moment.")
        if check:
            reasons += food_vision.reasons_from_check(check, log.to_dict().get("recipeName", "your meal"))

    if reasons:
        return {"accepted": False, "reasons": reasons, "mission": before}

    photos_col.add({
        "mealLogId": payload.mealLogId, "logDate": today_str(), "verified": True,
        "sha256": result["sha256"], "ahash": result["ahash"],
        "width": result["width"], "height": result["height"],
        "thumbnailB64": result["thumbnailB64"],
        "createdAt": now_local().isoformat(),
    })

    after = evaluate_mission(uid)
    if after["passed"] and not before["passed"]:
        coach_id = user.get("coachId")
        if coach_id:
            send_push_notification(
                coach_id, f"🏆 {user['name']} passed today's mission",
                "All meals photographed and macros on target.", data={"type": "mission_passed", "clientId": uid},
            )
    return {"accepted": True, "reasons": [], "mission": after}
