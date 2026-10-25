"""
Ingredient reference data and recipe validation for the FYP 2 optimizer.

Every ingredient has nutrition per 100 g (calories kcal, protein g, carbs g, fat g), a
category, and optimization limits expressed as multiples of the recipe's base weight.

Nutrition values are rounded, typical figures in the style of USDA FoodData Central
(foods are "as eaten": cooked rice, cooked chicken, etc.). Re-check them against your
chosen source before publishing results. Ingredients that are NOT in this table are never
given invented numbers: the recipe is marked "nutritionComplete = False" and the optimizer
refuses to treat it as an ingredient-level recipe.
"""
from typing import Optional

NUTRIENTS = ("calories", "protein", "carbs", "fat")

# name -> (kcal, protein g, carbs g, fat g, category)
REFERENCE = {
    "Chicken Breast": (165, 31.0, 0.0, 3.6, "protein"),
    "Jasmine Rice": (130, 2.7, 28.2, 0.3, "carb"),
    "Olive Oil": (884, 0.0, 0.0, 100.0, "fat"),
    "Broccoli": (35, 2.4, 7.2, 0.4, "veg"),
    "Soy Sauce": (53, 8.1, 4.9, 0.6, "seasoning"),
    "Garlic": (149, 6.4, 33.1, 0.5, "seasoning"),
    "Salmon Fillet": (206, 22.0, 0.0, 12.0, "protein"),
    "Quinoa": (120, 4.4, 21.3, 1.9, "carb"),
    "Asparagus": (20, 2.2, 3.9, 0.1, "veg"),
    "Egg Whites": (52, 10.9, 0.7, 0.2, "protein"),
    "Spinach": (23, 2.9, 3.6, 0.4, "veg"),
    "Bell Pepper": (31, 1.0, 6.0, 0.3, "veg"),
    "Greek Yogurt": (59, 10.2, 3.6, 0.4, "protein"),
    "Oats": (389, 16.9, 66.3, 6.9, "carb"),
    "Honey": (304, 0.3, 82.4, 0.0, "seasoning"),
    "Almonds": (579, 21.2, 21.6, 49.9, "fat"),
    "Tuna": (116, 25.5, 0.0, 0.8, "protein"),
    "Avocado": (160, 2.0, 8.5, 14.7, "fat"),
    "Whole Wheat Wrap": (310, 9.0, 50.0, 7.0, "carb"),
    "Lean Beef": (217, 26.1, 0.0, 11.8, "protein"),
    "Sweet Potato": (90, 2.0, 20.7, 0.2, "carb"),
    "Green Beans": (31, 1.8, 7.0, 0.2, "veg"),
    "Firm Tofu": (144, 17.3, 2.8, 8.7, "protein"),
    "Sesame Oil": (884, 0.0, 0.0, 100.0, "fat"),
    "Mixed Vegetables": (65, 3.3, 13.1, 0.5, "veg"),
    "Ground Turkey": (203, 27.1, 0.0, 10.4, "protein"),
    "Kidney Beans": (127, 8.7, 22.8, 0.5, "carb"),
    "Tomato Sauce": (29, 1.3, 6.6, 0.2, "veg"),
    "Onion": (40, 1.1, 9.3, 0.1, "seasoning"),
    "Milk": (61, 3.2, 4.8, 3.3, "other"),
    "Chia Seeds": (486, 16.5, 42.1, 30.7, "fat"),
    "Banana": (89, 1.1, 22.8, 0.3, "other"),
    "Shrimp": (99, 24.0, 0.2, 0.3, "protein"),
    "Zucchini Noodles": (17, 1.2, 3.1, 0.3, "veg"),
    "Parmesan": (431, 38.0, 4.1, 29.0, "fat"),
    "Whey Protein": (400, 80.0, 8.0, 7.0, "protein"),
    "Peanut Butter": (588, 25.0, 20.0, 50.0, "fat"),
    "Cottage Cheese": (98, 11.1, 3.4, 4.3, "protein"),
    "Mixed Berries": (57, 0.7, 14.0, 0.3, "other"),
    "Chickpeas": (164, 8.9, 27.4, 2.6, "carb"),
    "Mixed Greens": (20, 1.8, 3.6, 0.3, "veg"),
    "Tahini": (595, 17.0, 21.2, 53.8, "fat"),
    "Sirloin Steak": (206, 29.0, 0.0, 9.5, "protein"),
    "Butter": (717, 0.9, 0.1, 81.1, "fat"),
    "Oat Flour": (404, 14.7, 65.7, 9.1, "carb"),
    "Eggs": (143, 12.6, 0.7, 9.5, "protein"),
    "Maple Syrup": (260, 0.0, 67.0, 0.1, "seasoning"),
}

# category -> (min multiple, max multiple, adjustable). Multiples are of the recipe's base weight;
# they keep the dish cookable (a sauce is never 5x, a main protein is never removed).
CATEGORY_LIMITS = {
    "protein": (0.5, 2.5, True),
    "carb": (0.5, 2.5, True),
    "veg": (0.5, 2.0, True),
    "fat": (0.5, 1.5, True),
    "other": (0.5, 2.0, True),
    "seasoning": (1.0, 1.0, False),   # flavouring stays as written
}

# Liquids listed in ml are treated as 1 g = 1 ml (milk and egg whites are close to water).
SUPPORTED_UNITS = {"g", "ml"}


def per100_from_reference(name: str) -> Optional[dict]:
    row = REFERENCE.get(name)
    if not row:
        return None
    return {"calories": row[0], "protein": row[1], "carbs": row[2], "fat": row[3]}


def valid_per100(p: Optional[dict]) -> bool:
    """True when a per-100g block has all four numbers and they are physically sensible."""
    if not isinstance(p, dict):
        return False
    try:
        vals = {k: float(p[k]) for k in NUTRIENTS}
    except (KeyError, TypeError, ValueError):
        return False
    if any(v < 0 for v in vals.values()):
        return False
    if vals["calories"] > 900 or vals["protein"] + vals["carbs"] + vals["fat"] > 100.5:
        return False
    # Atwater cross-check: kcal from macros must be within 25% (+20 kcal slack) of stated kcal.
    est = 4 * vals["protein"] + 4 * vals["carbs"] + 9 * vals["fat"]
    return abs(est - vals["calories"]) <= 0.25 * max(vals["calories"], est) + 20


def build_items(recipe: dict) -> dict:
    """
    Turns a recipe document into optimizer items.
    Returns {"items": [...], "complete": bool, "problems": [str]}. An ingredient's own stored
    values win over the reference table; when neither exists the ingredient is reported as a
    problem instead of being guessed.
    """
    items, problems = [], []
    for ing in recipe.get("ingredients", []):
        name = ing.get("name", "?")
        base = ing.get("baseAmount")
        unit = ing.get("unit", "g")
        if not isinstance(base, (int, float)) or base <= 0:
            problems.append(f"{name}: base weight is missing or not positive")
            continue
        if unit not in SUPPORTED_UNITS:
            problems.append(f"{name}: unit '{unit}' is not supported")
            continue

        per100 = ing.get("per100g") or per100_from_reference(name)
        if per100 is None:
            problems.append(f"{name}: no nutrition data per 100 g")
            continue
        if not valid_per100(per100):
            problems.append(f"{name}: nutrition data per 100 g is invalid or inconsistent")
            continue

        category = (REFERENCE.get(name) or (0, 0, 0, 0, "other"))[4]
        lo_f, hi_f, adjustable = CATEGORY_LIMITS[category]
        if "adjustable" in ing:
            adjustable = bool(ing["adjustable"])
        lo = float(ing.get("minAmount", base * lo_f))
        hi = float(ing.get("maxAmount", base * hi_f))
        if not adjustable:
            lo = hi = float(base)
        if lo > hi or lo < 0:
            problems.append(f"{name}: minimum/maximum weight is invalid")
            continue

        items.append({
            "name": name, "emoji": ing.get("emoji", "🥗"), "unit": unit, "category": category,
            "base": float(base), "min": lo, "max": hi, "adjustable": adjustable,
            "per100g": {k: float(per100[k]) for k in NUTRIENTS},
        })

    return {"items": items, "complete": bool(items) and not problems, "problems": problems}


def recipe_totals(items: list, weights: Optional[list] = None) -> dict:
    """Nutrition of the whole recipe: sum(weight/100 * per100g) for each nutrient."""
    weights = weights or [i["base"] for i in items]
    return {k: sum(w / 100.0 * it["per100g"][k] for it, w in zip(items, weights)) for k in NUTRIENTS}


def enrich_recipe(recipe: dict) -> dict:
    """
    Returns a copy of the recipe with per-ingredient nutrition and limits stored on each ingredient and
    the recipe totals recalculated FROM those ingredients. Used by the seed and by the safe migration.
    The pre-migration totals are kept once under legacyTotals so nothing is lost. Ingredients without
    data are left untouched (never guessed) and the recipe is flagged nutritionComplete = False.
    """
    out = dict(recipe)
    built = build_items(recipe)
    by_name = {i["name"]: i for i in built["items"]}

    new_ings = []
    for ing in recipe.get("ingredients", []):
        ing = dict(ing)
        item = by_name.get(ing.get("name"))
        if item:
            ing.update({
                "per100g": item["per100g"], "category": item["category"],
                "minAmount": round(item["min"], 1), "maxAmount": round(item["max"], 1),
                "adjustable": item["adjustable"],
            })
        new_ings.append(ing)
    out["ingredients"] = new_ings
    out["nutritionComplete"] = built["complete"]
    out["nutritionProblems"] = built["problems"]

    if built["complete"]:
        if "legacyTotals" not in out and all(k in recipe for k in ("baseCalories", "baseProtein", "baseCarbs", "baseFat")):
            out["legacyTotals"] = {k: recipe[k] for k in ("baseCalories", "baseProtein", "baseCarbs", "baseFat")}
        t = recipe_totals(built["items"])
        out.update({"baseCalories": round(t["calories"]), "baseProtein": round(t["protein"], 1),
                    "baseCarbs": round(t["carbs"], 1), "baseFat": round(t["fat"], 1)})
        out.pop("refDailyCalories", None)     # the fixed 1,914 kcal reference is no longer used
    return out
