"""
Online recipe search through the Spoonacular API (free plan, no credit card).

Get a key at https://spoonacular.com/food-api and put it in backend/.env as
SPOONACULAR_API_KEY. Each search returns full recipes (ingredients, cooking steps and
nutrition per serving). They are converted to NutriFit's recipe format and saved to
Firestore, so afterwards they behave exactly like the built-in recipes: they scale to
the client's calorie target, can be logged, and show up in suggestions. Saved recipes
are never downloaded again, which keeps the free daily quota for new searches.
"""
import logging
import os
import time
from concurrent.futures import ThreadPoolExecutor, TimeoutError as FutureTimeout
from typing import List, Optional

import requests

logger = logging.getLogger("nutrifit")

SEARCH_URL = "https://api.spoonacular.com/recipes/complexSearch"
DEADLINE_SECONDS = 15
_POOL = ThreadPoolExecutor(max_workers=2)


class OnlineRecipesUnavailable(RuntimeError):
    """The service could not be reached, is over its quota, or no key is configured."""


def is_enabled() -> bool:
    return bool(os.environ.get("SPOONACULAR_API_KEY"))


def _emoji_for(title: str, dish_types: list) -> str:
    text = f"{title} {' '.join(dish_types or [])}".lower()
    for words, emoji in (
        (("soup", "stew", "chili", "curry"), "🍲"), (("salad", "bowl"), "🥗"), (("pancake", "waffle"), "🥞"),
        (("egg", "omelet", "omelette", "breakfast"), "🍳"), (("chicken",), "🍗"), (("fish", "salmon", "tuna"), "🐟"),
        (("shrimp", "prawn"), "🍤"), (("beef", "steak"), "🥩"), (("rice",), "🍚"), (("noodle", "pasta", "spaghetti"), "🍝"),
        (("sandwich", "wrap", "burger"), "🥪"), (("smoothie", "shake", "drink"), "🥤"), (("dessert", "cake", "cookie"), "🍰"),
    ):
        if any(w in text for w in words):
            return emoji
    return "🍽️"


def _nutrient(nutrients: list, name: str) -> Optional[float]:
    for n in nutrients or []:
        if str(n.get("name", "")).lower() == name.lower():
            try:
                return float(n.get("amount"))
            except (TypeError, ValueError):
                return None
    return None


def _tag_for(protein: float, carbs: float, minutes: Optional[int]) -> str:
    if protein >= 30:
        return "Protein"
    if carbs <= 20:
        return "Low Carb"
    if minutes and minutes <= 20:
        return "Quick Prep"
    return "Balanced"


def convert(item: dict) -> Optional[dict]:
    """Converts one Spoonacular recipe to NutriFit's format, or None if it lacks anything we need."""
    nutrients = (item.get("nutrition") or {}).get("nutrients")
    calories, protein = _nutrient(nutrients, "Calories"), _nutrient(nutrients, "Protein")
    carbs, fat = _nutrient(nutrients, "Carbohydrates"), _nutrient(nutrients, "Fat")
    if None in (calories, protein, carbs, fat) or not 50 <= calories <= 2500:
        return None

    servings = item.get("servings") or 1
    try:
        servings = max(float(servings), 1.0)
    except (TypeError, ValueError):
        servings = 1.0

    ingredients = []
    for ing in item.get("extendedIngredients") or []:
        metric = (ing.get("measures") or {}).get("metric") or {}
        amount = metric.get("amount", ing.get("amount"))
        unit = (metric.get("unitShort") or "").strip()
        try:
            per_serving = round(float(amount) / servings, 1)
        except (TypeError, ValueError):
            continue
        name = str(ing.get("nameClean") or ing.get("name") or "").strip().title()
        if per_serving <= 0 or not name:
            continue
        ingredients.append({"name": name, "emoji": "🥗", "baseAmount": per_serving, "unit": unit or "pc"})

    steps = []
    for block in item.get("analyzedInstructions") or []:
        steps += [str(s.get("step", "")).strip() for s in block.get("steps", []) if s.get("step")]

    if not ingredients or not steps or not item.get("title"):
        return None

    minutes = item.get("readyInMinutes")
    return {
        "name": str(item["title"]).strip(),
        "emoji": _emoji_for(item["title"], item.get("dishTypes")),
        "tag": _tag_for(protein, carbs, minutes),
        "baseProtein": round(protein), "baseCarbs": round(carbs), "baseFat": round(fat), "baseCalories": round(calories),
        "ingredients": ingredients, "steps": steps,
        "readyInMinutes": minutes, "servings": servings,
        "source": "Spoonacular", "sourceUrl": item.get("sourceUrl") or item.get("spoonacularSourceUrl"),
        "externalId": f"sp_{item.get('id')}",
    }


def _fetch(query: str, number: int) -> List[dict]:
    resp = requests.get(SEARCH_URL, timeout=(5, 12), params={
        "apiKey": os.environ["SPOONACULAR_API_KEY"], "query": query, "number": number,
        "addRecipeInformation": "true", "addRecipeNutrition": "true", "fillIngredients": "true",
        "instructionsRequired": "true",
    })
    if resp.status_code == 402:
        raise OnlineRecipesUnavailable("The free daily limit of the recipe service has been reached. Try again tomorrow.")
    resp.raise_for_status()
    return resp.json().get("results", [])


def search_online(query: str, number: int = 8) -> List[dict]:
    """Returns converted recipes (each with an 'externalId'); raises OnlineRecipesUnavailable on any failure."""
    if not is_enabled():
        raise OnlineRecipesUnavailable("Online recipe search is not set up yet. Add SPOONACULAR_API_KEY to backend/.env.")
    started = time.monotonic()
    try:
        raw = _POOL.submit(_fetch, query, number).result(timeout=DEADLINE_SECONDS)
    except OnlineRecipesUnavailable:
        raise
    except (requests.RequestException, FutureTimeout, ValueError) as e:
        logger.warning("Online recipe search failed after %.1fs: %s", time.monotonic() - started, repr(e))
        raise OnlineRecipesUnavailable("The online recipe service is not responding. Please try again in a moment.")
    logger.info("Online recipe search '%s' returned %d in %.1fs", query, len(raw), time.monotonic() - started)
    return [r for r in (convert(i) for i in raw) if r]
