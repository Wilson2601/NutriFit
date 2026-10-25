"""
Planned vs consumed meals, and the daily nutrition / adherence endpoints.

Only POST /meals/consume (and food logging) creates intake. Previewing, optimising or planning a
recipe never changes today's totals.
"""
from fastapi import APIRouter, Depends, HTTPException, Query

from app import nutrition
from app.auth import get_current_user
from app.firebase import db
from app.notifications import send_push_notification
from app.ingredient_data import NUTRIENTS, build_items, recipe_totals
from app.schemas import MealRecordRequest, MealEditRequest
from app.meal_allocation import AllocationError, normalise_meal_type, normalise_future
from app.routers.grocery import add_ingredients
from app.timeutil import now_local, today_str

router = APIRouter(tags=["meals"])

MAX_WEIGHT_G = 3000
MIN_PORTION, MAX_PORTION = 0.2, 4.0


def _need_user(user):
    if user["role"] != "user":
        raise HTTPException(status_code=403, detail="Requires user role")


def _user_col(uid, name):
    return db.collection("users").document(uid).collection(name)


def compute_record(recipe: dict, ingredients=None, portion_factor=None) -> dict:
    """Server-side nutrition for a meal. The client only sends weights; it can never send macros."""
    built = build_items(recipe)
    if built["complete"]:
        if not ingredients:
            raise HTTPException(status_code=422, detail="Ingredient weights are required for this recipe")
        by_name = {i["name"]: i for i in built["items"]}
        weights = {}
        for ing in ingredients:
            if ing.name not in by_name:
                raise HTTPException(status_code=422, detail=f"'{ing.name}' is not an ingredient of this recipe")
            if not 0 <= ing.amount <= MAX_WEIGHT_G:
                raise HTTPException(status_code=422, detail=f"Weight for {ing.name} must be between 0 and {MAX_WEIGHT_G}")
            weights[ing.name] = float(ing.amount)
        if sum(weights.values()) <= 0:
            raise HTTPException(status_code=422, detail="At least one ingredient weight must be above zero")
        items = built["items"]
        ws = [weights.get(i["name"], 0.0) for i in items]
        totals = recipe_totals(items, ws)
        stored = [{"name": i["name"], "unit": i["unit"], "amount": round(w, 1)} for i, w in zip(items, ws)]
        return {"macros": {k: round(v, 1) for k, v in totals.items()}, "ingredients": stored, "portionFactor": None}

    if portion_factor is None:
        raise HTTPException(status_code=422, detail="A portion factor is required for this recipe")
    if not MIN_PORTION <= portion_factor <= MAX_PORTION:
        raise HTTPException(status_code=422, detail=f"Portion must be between {MIN_PORTION} and {MAX_PORTION}")
    try:
        base = {k: float(recipe[f"base{k.capitalize()}"]) for k in NUTRIENTS}
    except (KeyError, TypeError, ValueError):
        raise HTTPException(status_code=422, detail="This recipe has no usable nutrition data")
    return {"macros": {k: round(v * portion_factor, 1) for k, v in base.items()}, "ingredients": None,
            "portionFactor": round(portion_factor, 2)}


def _recipe_or_404(recipe_id):
    snap = db.collection("recipes").document(recipe_id).get()
    if not snap.exists:
        raise HTTPException(status_code=404, detail="Recipe not found")
    return snap.to_dict()


def _context(payload):
    try:
        return normalise_meal_type(payload.mealType), (normalise_future(payload.futureMeal) if payload.futureMeal else None)
    except AllocationError as e:
        raise HTTPException(status_code=422, detail=str(e))


# ---------- planned meals (never counted as eaten) ----------

@router.post("/meals/plan", status_code=201)
def plan_meal(payload: MealRecordRequest, user: dict = Depends(get_current_user)):
    _need_user(user)
    recipe = _recipe_or_404(payload.recipeId)
    meal_type, future = _context(payload)
    rec = compute_record(recipe, payload.ingredients, payload.portionFactor)
    _, ref = _user_col(user["uid"], "plannedMeals").add({
        "recipeId": payload.recipeId, "recipeName": recipe["name"], "recipeEmoji": recipe.get("emoji", "🍽️"),
        "mealType": meal_type, "futureMeal": future, "status": "planned",
        "planDate": today_str(), "createdAt": now_local().isoformat(),
        **rec["macros"], "ingredients": rec["ingredients"], "portionFactor": rec["portionFactor"],
    })
    # Planning also puts what you need to buy on the shopping list.
    emojis = {i.get("name"): i.get("emoji", "🛒") for i in recipe.get("ingredients", [])}
    if rec["ingredients"]:
        shop = [{"name": i["name"], "unit": i["unit"], "scaledAmount": i["amount"], "emoji": emojis.get(i["name"], "🛒")} for i in rec["ingredients"] if i["amount"] > 0]
    else:
        f = rec["portionFactor"] or 1
        shop = [{"name": i["name"], "unit": i.get("unit", "g"), "scaledAmount": round(i["baseAmount"] * f, 1), "emoji": i.get("emoji", "🛒")} for i in recipe.get("ingredients", [])]
    add_ingredients(user["uid"], shop, payload.recipeId)
    return {"id": ref.id, "status": "planned", "macros": rec["macros"], "groceryAdded": len(shop)}


@router.get("/meals/planned")
def list_planned(user: dict = Depends(get_current_user)):
    _need_user(user)
    rows = [{"id": s.id, **s.to_dict()} for s in _user_col(user["uid"], "plannedMeals").stream()]
    rows.sort(key=lambda r: r.get("createdAt", ""), reverse=True)
    return {"planned": rows}


@router.get("/meals/planned/{planned_id}")
def planned_detail(planned_id: str, user: dict = Depends(get_current_user)):
    """A planned meal with the weights chosen when it was planned, plus the cooking steps."""
    _need_user(user)
    snap = _user_col(user["uid"], "plannedMeals").document(planned_id).get()
    if not snap.exists:
        raise HTTPException(status_code=404, detail="Planned meal not found")
    plan = {"id": planned_id, **snap.to_dict()}
    rs = db.collection("recipes").document(plan["recipeId"]).get()
    recipe = rs.to_dict() if rs.exists else {}
    meta = {i.get("name"): i for i in recipe.get("ingredients", [])}
    if plan.get("ingredients"):
        ingredients = [{"name": i["name"], "emoji": meta.get(i["name"], {}).get("emoji", "🥗"), "unit": i["unit"], "amount": i["amount"]} for i in plan["ingredients"]]
    else:
        f = plan.get("portionFactor") or 1
        ingredients = [{"name": i["name"], "emoji": i.get("emoji", "🥗"), "unit": i.get("unit", "g"), "amount": round(i["baseAmount"] * f, 1)} for i in recipe.get("ingredients", [])]
    return {
        "planned": plan, "ingredients": ingredients, "steps": recipe.get("steps", []),
        "source": recipe.get("source"), "sourceUrl": recipe.get("sourceUrl"), "readyInMinutes": recipe.get("readyInMinutes"),
    }


@router.delete("/meals/planned/{planned_id}", status_code=204)
def delete_planned(planned_id: str, user: dict = Depends(get_current_user)):
    _need_user(user)
    ref = _user_col(user["uid"], "plannedMeals").document(planned_id)
    if not ref.get().exists:
        raise HTTPException(status_code=404, detail="Planned meal not found")
    ref.delete()


# ---------- consumed meals (the only thing that counts as intake) ----------

@router.post("/meals/consume", status_code=201)
def consume_meal(payload: MealRecordRequest, user: dict = Depends(get_current_user)):
    _need_user(user)
    uid = user["uid"]
    logs = _user_col(uid, "mealLogs")

    if payload.requestId:
        for s in logs.stream():
            if s.to_dict().get("requestId") == payload.requestId:
                return {"id": s.id, "duplicate": True, "macros": {k: s.to_dict().get(k) for k in NUTRIENTS}}

    recipe = _recipe_or_404(payload.recipeId)
    meal_type, future = _context(payload)
    rec = compute_record(recipe, payload.ingredients, payload.portionFactor)
    _, ref = logs.add({
        "recipeId": payload.recipeId, "recipeName": recipe["name"], "recipeEmoji": recipe.get("emoji", "🍽️"),
        "mealType": meal_type, "futureMeal": future, "status": "consumed",
        "logDate": today_str(), "loggedAt": now_local().isoformat(), "requestId": payload.requestId,
        **rec["macros"], "ingredients": rec["ingredients"], "portionFactor": rec["portionFactor"],
    })
    if payload.plannedId:
        planned = _user_col(uid, "plannedMeals").document(payload.plannedId)
        plan_snap = planned.get()
        if plan_snap.exists:
            # Keep the plan on the log so "Undo" can put it back.
            _user_col(uid, "mealLogs").document(ref.id).update({"plannedSnapshot": plan_snap.to_dict(), "plannedId": payload.plannedId})
            planned.delete()
    if user.get("coachId"):
        send_push_notification(
            user["coachId"], f"🍽️ {user['name']} logged a meal",
            f"{recipe['name']} · {round(rec['macros'].get('calories', 0))} kcal",
            data={"type": "meal_logged", "clientId": uid},
        )
    return {"id": ref.id, "duplicate": False, "macros": rec["macros"]}


@router.put("/meals/{meal_id}")
def edit_meal(meal_id: str, payload: MealEditRequest, user: dict = Depends(get_current_user)):
    _need_user(user)
    ref = _user_col(user["uid"], "mealLogs").document(meal_id)
    snap = ref.get()
    if not snap.exists:
        raise HTTPException(status_code=404, detail="Meal not found")
    log = snap.to_dict()
    update = {}

    if payload.mealType:
        try:
            update["mealType"] = normalise_meal_type(payload.mealType)
        except AllocationError as e:
            raise HTTPException(status_code=422, detail=str(e))

    if payload.grams is not None:                       # a single food logged by weight
        per100 = log.get("per100g")
        if not per100:
            raise HTTPException(status_code=422, detail="This entry cannot be edited by weight")
        if not 1 <= payload.grams <= 5000:
            raise HTTPException(status_code=422, detail="Amount must be between 1 and 5000 g")
        update.update({k: round(per100[k] * payload.grams / 100, 1) for k in NUTRIENTS})
        update["grams"] = payload.grams
    elif payload.ingredients is not None or payload.portionFactor is not None:
        if not log.get("recipeId"):
            raise HTTPException(status_code=422, detail="This entry is not a recipe")
        rec = compute_record(_recipe_or_404(log["recipeId"]), payload.ingredients, payload.portionFactor)
        update.update(rec["macros"])
        update["ingredients"], update["portionFactor"] = rec["ingredients"], rec["portionFactor"]

    if not update:
        raise HTTPException(status_code=422, detail="Nothing to change")
    update["editedAt"] = now_local().isoformat()
    ref.update(update)
    return {"id": meal_id, **{k: update[k] for k in update if k in NUTRIENTS}}


@router.post("/meals/{meal_id}/undo")
def undo_meal(meal_id: str, user: dict = Depends(get_current_user)):
    """Takes back a logged meal. If it came from a plan, the plan returns to Today's Meals."""
    _need_user(user)
    uid = user["uid"]
    ref = _user_col(uid, "mealLogs").document(meal_id)
    snap = ref.get()
    if not snap.exists:
        raise HTTPException(status_code=404, detail="Meal not found")
    log = snap.to_dict()
    plan, plan_id = log.get("plannedSnapshot"), log.get("plannedId")
    restored = False
    if plan and plan_id:
        _user_col(uid, "plannedMeals").document(plan_id).set(plan)
        restored = True
    ref.delete()
    return {"undone": meal_id, "plannedRestored": restored, "plannedId": plan_id if restored else None}


@router.delete("/meals/{meal_id}", status_code=204)
def delete_meal(meal_id: str, user: dict = Depends(get_current_user)):
    _need_user(user)
    ref = _user_col(user["uid"], "mealLogs").document(meal_id)
    if not ref.get().exists:
        raise HTTPException(status_code=404, detail="Meal not found")
    ref.delete()


# ---------- daily nutrition + adherence ----------

@router.get("/nutrition/summary")
def nutrition_summary(date: str = Query(None, pattern=r"^\d{4}-\d{2}-\d{2}$"), user: dict = Depends(get_current_user)):
    return nutrition.daily_summary(user["uid"], date)


@router.get("/nutrition/adherence")
def nutrition_adherence(days: int = Query(7, ge=1, le=90), includeToday: bool = False, user: dict = Depends(get_current_user)):
    return nutrition.adherence_report(user["uid"], days, includeToday)


@router.get("/nutrition/config")
def nutrition_config(user: dict = Depends(get_current_user)):
    from app.meal_allocation import load_config
    cfg = load_config()
    return {"adherence": nutrition.adherence_config(),
            "allocation": {"futureFraction": cfg.future_fraction, "mealCap": cfg.meal_cap}}
