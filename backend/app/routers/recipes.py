from fastapi import APIRouter, Depends, HTTPException, Query

from app import nutrition, online_recipes
from app.firebase import db
from app.auth import get_current_user
from app.ingredient_data import NUTRIENTS, build_items
from app.meal_allocation import AllocationError, allocate
from app.optimizer import OptimizerError, optimize, optimize_uniform
from app.schemas import MealContextRequest

router = APIRouter(prefix="/recipes", tags=["recipes"])


@router.get("")
def list_recipes(tag: str = None, search: str = None, user: dict = Depends(get_current_user)):
    words = (search or "").lower().split()
    docs = db.collection("recipes").stream()
    recipes = []
    for d in docs:
        r = d.to_dict()
        r["id"] = d.id
        if tag and tag != "All" and r.get("tag") != tag:
            continue
        if words:
            # Every search word must appear in the recipe name or one of its ingredients.
            haystack = (r.get("name", "") + " " + " ".join(i.get("name", "") for i in r.get("ingredients", []))).lower()
            if not all(w in haystack for w in words):
                continue
        recipes.append(r)
    return {"recipes": recipes}


@router.get("/online")
def search_online_recipes(q: str = Query(..., min_length=2, max_length=60), user: dict = Depends(get_current_user)):
    """
    Searches the online recipe service, saves every new recipe to Firestore, and returns them.
    Recipes that were saved earlier are reused as they are (nothing is overwritten).
    """
    try:
        found = online_recipes.search_online(q.strip())
    except online_recipes.OnlineRecipesUnavailable as e:
        raise HTTPException(status_code=503, detail=str(e))

    results = []
    for recipe in found:
        doc_id = recipe["externalId"]
        ref = db.collection("recipes").document(doc_id)
        snap = ref.get()
        if snap.exists:
            saved = snap.to_dict()
        else:
            ref.set(recipe)
            saved = recipe
        results.append({**saved, "id": doc_id})
    return {"recipes": results}


def optimize_for(recipe: dict, allocated: dict) -> dict:
    """Ingredient-level optimisation when the recipe has full ingredient data, otherwise a clearly labelled portion fallback."""
    built = build_items(recipe)
    if built["complete"]:
        result = optimize(built["items"], allocated)
        result["problems"] = []
        return result
    try:
        per_serving = {k: float(recipe[f"base{k.capitalize()}"]) for k in NUTRIENTS}
    except (KeyError, TypeError, ValueError):
        raise HTTPException(status_code=422, detail="This recipe has no usable nutrition data: " + "; ".join(built["problems"] or ["missing values"]))
    result = optimize_uniform(recipe.get("name", "Recipe"), per_serving, allocated)
    f = result["factor"]
    # Show the real ingredients multiplied by the single portion factor (nothing is adjusted individually).
    result["ingredients"] = [
        {"name": i["name"], "emoji": i.get("emoji", "🥗"), "unit": i.get("unit", "g"),
         "originalAmount": i["baseAmount"], "optimizedAmount": round(i["baseAmount"] * f, 1),
         "adjustable": True, "limit": None, "nutrition": None}
        for i in recipe.get("ingredients", [])
    ]
    result["problems"] = built["problems"]
    result["warnings"].insert(0, "Ingredient nutrition data is not available for this recipe, so only the portion size was adjusted.")
    return result


@router.get("/suggested")
def suggested_recipes(mealType: str = "Lunch", futureMeal: str = "not_sure", user: dict = Depends(get_current_user)):
    """Ranks recipes by how closely each one, optimised for the meal target, matches what is still needed today."""
    summary = nutrition.daily_summary(user["uid"], with_meals=False)
    try:
        alloc = allocate({k: summary["target"][k] for k in NUTRIENTS}, summary["consumed"], mealType, futureMeal)
    except AllocationError as e:
        raise HTTPException(status_code=422, detail=str(e))

    ranked = []
    for d in db.collection("recipes").stream():
        r = d.to_dict()
        built = build_items(r)
        if not built["complete"]:
            continue
        res = optimize(built["items"], alloc["allocated"])
        errs = [abs(c["differencePct"]) for c in res["comparison"].values() if c["differencePct"] is not None]
        mean_err = sum(errs) / len(errs) if errs else 0.0
        ranked.append({
            "id": d.id, "name": r["name"], "emoji": r.get("emoji", "🍽️"),
            "matchPct": max(0, round(100 - mean_err)), "macros": res["nutrition"], "_err": mean_err,
        })
    ranked.sort(key=lambda x: (x["_err"], x["name"]))
    for x in ranked:
        x.pop("_err")
    return {"remaining": alloc["remaining"], "allocated": alloc["allocated"], "suggestions": ranked[:5]}


@router.post("/{recipe_id}/optimize")
def optimize_recipe(recipe_id: str, payload: MealContextRequest, user: dict = Depends(get_current_user)):
    """Preview only: nothing is saved and nothing counts as eaten."""
    snap = db.collection("recipes").document(recipe_id).get()
    if not snap.exists:
        raise HTTPException(status_code=404, detail="Recipe not found")
    recipe = snap.to_dict()

    summary = nutrition.daily_summary(user["uid"], with_meals=False)
    try:
        alloc = allocate({k: summary["target"][k] for k in NUTRIENTS}, summary["consumed"], payload.mealType, payload.futureMeal)
        result = optimize_for(recipe, alloc["allocated"])
    except (AllocationError, OptimizerError) as e:
        raise HTTPException(status_code=422, detail=str(e))

    if all(v <= 0 for v in alloc["allocated"].values()):
        result["warnings"].insert(0, "There is nothing left to allocate for this meal, so the recipe is shown at its smallest size.")

    return {
        "recipe": {"id": recipe_id, "name": recipe["name"], "emoji": recipe.get("emoji", "🍽️")},
        "allocation": alloc,
        "daily": {"target": summary["target"], "consumed": summary["consumed"], "remaining": summary["remaining"]},
        "result": result,
        "steps": recipe.get("steps", []),
        "source": recipe.get("source"), "sourceUrl": recipe.get("sourceUrl"),
        "readyInMinutes": recipe.get("readyInMinutes"),
    }
