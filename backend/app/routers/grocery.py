import re
from fastapi import APIRouter, Depends, HTTPException

from app.firebase import db
from app.auth import get_current_user
from app.schemas import GroceryItemRequest, GroceryToggleRequest
from app import nutrition
from app.meal_allocation import allocate
from app.ingredient_data import NUTRIENTS

router = APIRouter(prefix="/grocery", tags=["grocery"])

_CATEGORY_PATTERNS = [
    (re.compile(r"chicken|egg|yogurt|salmon|tuna|fish|beef", re.I), "Proteins"),
    (re.compile(r"rice|oats|quinoa|bread|wrap", re.I), "Carbohydrates"),
    (re.compile(r"broccoli|spinach|garlic|avocado|vegetable|tomato|lettuce|asparagus|pepper", re.I), "Vegetables"),
    (re.compile(r"oil|almond|nuts", re.I), "Fats & Oils"),
]


def _category_for(name: str) -> str:
    for pattern, category in _CATEGORY_PATTERNS:
        if pattern.search(name):
            return category
    return "Other"


def _items_collection(uid: str):
    return db.collection("users").document(uid).collection("groceryItems")


def add_ingredients(uid: str, scaled: list, recipe_id: str) -> None:
    """Adds [{name, emoji, unit, scaledAmount}] to the shopping list, merging with unchecked items of the same name and unit."""
    items_col = _items_collection(uid)
    existing = {(i.to_dict()["name"], i.to_dict()["unit"]): i for i in items_col.stream() if not i.to_dict().get("checked")}
    for ing in scaled:
        key = (ing["name"], ing["unit"])
        if key in existing:
            doc_ref = items_col.document(existing[key].id)
            current_amount = existing[key].to_dict().get("amount") or 0
            doc_ref.update({"amount": round(current_amount + ing["scaledAmount"], 1)})
        else:
            items_col.add({
                "name": ing["name"], "emoji": ing.get("emoji", "🛒"), "category": _category_for(ing["name"]),
                "amount": ing["scaledAmount"], "unit": ing["unit"], "checked": False, "sourceRecipeId": recipe_id,
            })


@router.get("")
def list_items(user: dict = Depends(get_current_user)):
    items = []
    recipe_ids = set()
    for snap in _items_collection(user["uid"]).stream():
        item = snap.to_dict()
        item["id"] = snap.id
        items.append(item)
        if item.get("sourceRecipeId"):
            recipe_ids.add(item["sourceRecipeId"])
    items.sort(key=lambda i: i.get("category", "Other"))
    return {"items": items, "recipe_count": len(recipe_ids)}


@router.post("", status_code=201)
def add_item(payload: GroceryItemRequest, user: dict = Depends(get_current_user)):
    _, doc = _items_collection(user["uid"]).add({
        "name": payload.name, "emoji": payload.emoji, "category": payload.category,
        "amount": payload.amount, "unit": payload.unit, "checked": False, "sourceRecipeId": None,
    })
    return {"id": doc.id}


@router.post("/from-recipe/{recipe_id}", status_code=201)
def add_from_recipe(recipe_id: str, user: dict = Depends(get_current_user)):
    snap = db.collection("recipes").document(recipe_id).get()
    if not snap.exists:
        raise HTTPException(status_code=404, detail="Recipe not found")
    recipe = snap.to_dict()

    # Shopping list uses the same optimiser as the recipe screen (Lunch, "not sure" by default).
    from app.routers.recipes import optimize_for
    summary = nutrition.daily_summary(user["uid"], with_meals=False)
    alloc = allocate({k: summary["target"][k] for k in NUTRIENTS}, summary["consumed"], "Lunch", "not_sure")
    result = optimize_for(recipe, alloc["allocated"])
    scaled = [{"name": i["name"], "emoji": i["emoji"], "unit": i["unit"], "scaledAmount": i["optimizedAmount"]} for i in result["ingredients"]]

    add_ingredients(user["uid"], scaled, recipe_id)

    return list_items(user)


@router.patch("/{item_id}")
def toggle_item(item_id: str, payload: GroceryToggleRequest, user: dict = Depends(get_current_user)):
    doc = _items_collection(user["uid"]).document(item_id)
    if not doc.get().exists:
        raise HTTPException(status_code=404, detail="Item not found")
    doc.update({"checked": payload.checked})
    return {"ok": True}


@router.delete("")
def clear_items(scope: str = "checked", user: dict = Depends(get_current_user)):
    """Removes checked items (default) or the whole list (scope=all)."""
    if scope not in ("checked", "all"):
        raise HTTPException(status_code=422, detail="scope must be 'checked' or 'all'")
    col = _items_collection(user["uid"])
    removed = 0
    for snap in list(col.stream()):
        if scope == "all" or snap.to_dict().get("checked"):
            col.document(snap.id).delete()
            removed += 1
    return {"removed": removed}


@router.delete("/{item_id}")
def delete_item(item_id: str, user: dict = Depends(get_current_user)):
    doc = _items_collection(user["uid"]).document(item_id)
    if not doc.get().exists:
        raise HTTPException(status_code=404, detail="Item not found")
    doc.delete()
    return {"ok": True}
