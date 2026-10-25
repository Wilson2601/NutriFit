"""Search free online food databases and log any food by weight."""
from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException, Query

from app import foods
from app.auth import get_current_user
from app.firebase import db
from app.schemas import FoodLogRequest
from app.timeutil import now_local, today_str

router = APIRouter(prefix="/foods", tags=["foods"])

MAX_GRAMS = 5000


@router.get("/search")
def search(q: str = Query(..., min_length=2, max_length=80), user: dict = Depends(get_current_user)):
    return foods.search_foods(q.strip())


@router.post("/log", status_code=201)
def log_food(payload: FoodLogRequest, user: dict = Depends(get_current_user)):
    if user["role"] != "user":
        raise HTTPException(status_code=403, detail="Requires user role")

    name = payload.name.strip()
    if not name:
        raise HTTPException(status_code=422, detail="Food name is required")
    if not 1 <= payload.grams <= MAX_GRAMS:
        raise HTTPException(status_code=422, detail=f"Amount must be between 1 and {MAX_GRAMS} g")

    per100g = {
        "calories": payload.caloriesPer100g, "protein": payload.proteinPer100g,
        "carbs": payload.carbsPer100g, "fat": payload.fatPer100g,
    }
    if not foods._valid_per100g(per100g):
        raise HTTPException(status_code=422, detail="Those nutrition values are not realistic for 100 g of food")

    if payload.requestId:
        for snap in db.collection("users").document(user["uid"]).collection("mealLogs").stream():
            if snap.to_dict().get("requestId") == payload.requestId:
                d = snap.to_dict()
                return {"id": snap.id, "duplicate": True, "macros": {k: d.get(k) for k in per100g}}

    factor = payload.grams / 100
    macros = {k: round(v * factor, 1) for k, v in per100g.items()}
    _, ref = db.collection("users").document(user["uid"]).collection("mealLogs").add({
        "recipeId": None, "recipeName": name, "recipeEmoji": "🍽️",
        "mealType": payload.mealType, "logDate": today_str(),
        "loggedAt": now_local().isoformat(),
        "foodSource": payload.source, "grams": payload.grams, "per100g": per100g,
        "status": "consumed", "requestId": payload.requestId,
        **macros,
    })
    return {"id": ref.id, "duplicate": False, "macros": macros}
