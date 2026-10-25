from fastapi import APIRouter, Depends

from app import nutrition
from app.auth import get_current_user

router = APIRouter(tags=["targets"])


def _current_target(uid: str) -> dict:
    """Kept for callers that need the coach's current prescription (proteinG, carbsG, fatG, calories)."""
    return nutrition.get_target(uid)


@router.get("/targets/me")
def my_target(user: dict = Depends(get_current_user)):
    return {"target": nutrition.get_target(user["uid"])}


@router.get("/progress/today")
def progress_today(user: dict = Depends(get_current_user)):
    """Dashboard numbers. Uses the shared nutrition service, so it always matches food history and the coach view."""
    s = nutrition.daily_summary(user["uid"])
    t = nutrition.get_target(user["uid"])
    meals = [
        {"id": m["id"], "mealType": m.get("mealType"), "recipeName": m.get("recipeName"), "recipeEmoji": m.get("recipeEmoji"),
         "protein": m.get("protein"), "carbs": m.get("carbs"), "fat": m.get("fat"), "calories": m.get("calories")}
        for m in reversed(s["meals"])
    ]
    cal = s["components"]["calories"]
    from app.firebase import db
    from app.timeutil import today_str
    planned = [
        {"id": p.id, "recipeId": p.to_dict().get("recipeId"), "recipeName": p.to_dict().get("recipeName"),
         "recipeEmoji": p.to_dict().get("recipeEmoji"), "mealType": p.to_dict().get("mealType"),
         "calories": p.to_dict().get("calories"), "protein": p.to_dict().get("protein"),
         "carbs": p.to_dict().get("carbs"), "fat": p.to_dict().get("fat")}
        for p in db.collection("users").document(user["uid"]).collection("plannedMeals").stream()
        if p.to_dict().get("planDate") == today_str()
    ]
    return {
        "planned": planned,
        "target": t, "totals": s["consumed"], "meals": meals,
        "percent_complete": round(cal["percent"]) if cal["percent"] is not None else 0,
        "remaining": s["remaining"], "components": s["components"], "adherent": s["adherent"],
    }
