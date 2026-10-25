"""
Free online food databases, searched live and merged into one list.

  - USDA FoodData Central: generic foods (chicken breast, white rice, egg ...).
    Free API key from https://fdc.nal.usda.gov/api-key-signup (DEMO_KEY works for light testing).
  - Open Food Facts: packaged and local products, including many sold in Malaysia. No key needed.

Every result is normalised to nutrients per 100 g so one logging flow handles all sources.
One source being down never breaks the search: the other still answers and a warning is returned.
"""
import logging
import os
import time
from concurrent.futures import ThreadPoolExecutor, TimeoutError as FutureTimeout
from typing import List, Optional

import requests

logger = logging.getLogger("nutrifit")

USDA_URL = "https://api.nal.usda.gov/fdc/v1/foods/search"
OFF_URL = "https://world.openfoodfacts.org/cgi/search.pl"  # older endpoint, often busy
OFF_NEW_URL = "https://search.openfoodfacts.org/search"  # newer search service
USER_AGENT = "NutriFit-FYP/1.0 (student project)"
DEADLINE_SECONDS = 10
CACHE_SECONDS = 600

_POOL = ThreadPoolExecutor(max_workers=6)
_cache: dict = {}


def _num(value) -> Optional[float]:
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def _valid_per100g(p: dict) -> bool:
    """Rejects obviously broken database rows (missing data, impossible values)."""
    if any(p.get(k) is None for k in ("calories", "protein", "carbs", "fat")):
        return False
    if not 0 <= p["calories"] <= 900:
        return False
    return 0 <= p["protein"] + p["carbs"] + p["fat"] <= 101


def parse_usda(payload: dict) -> List[dict]:
    items = []
    for food in payload.get("foods", []):
        nutrients = {}
        for n in food.get("foodNutrients", []):
            nutrients[n.get("nutrientId")] = _num(n.get("value"))
        per100g = {
            # 1008 = Energy (kcal), 1003 = Protein, 1005 = Carbohydrate, 1004 = Total fat
            "calories": nutrients.get(1008) if nutrients.get(1008) is not None else nutrients.get(2047),
            "protein": nutrients.get(1003),
            "carbs": nutrients.get(1005),
            "fat": nutrients.get(1004),
        }
        if not _valid_per100g(per100g):
            continue
        items.append({
            "id": f"usda:{food.get('fdcId')}", "source": "USDA",
            "name": str(food.get("description", "")).title(), "brand": None,
            "per100g": {k: round(v, 1) for k, v in per100g.items()}, "servingG": 100,
        })
    return items


def _text(value) -> str:
    """Fields may be a string, a list of strings, or a language dict depending on the endpoint."""
    if isinstance(value, list):
        value = value[0] if value else ""
    elif isinstance(value, dict):
        value = value.get("en") or next(iter(value.values()), "")
    return str(value or "").strip()


def parse_off(payload: dict) -> List[dict]:
    items = []
    # The older endpoint answers with "products", the newer search service with "hits".
    for prod in payload.get("products") or payload.get("hits") or []:
        try:
            name = _text(prod.get("product_name"))
            n = prod.get("nutriments") or {}
            per100g = {
                "calories": _num(n.get("energy-kcal_100g")),
                "protein": _num(n.get("proteins_100g")),
                "carbs": _num(n.get("carbohydrates_100g")),
                "fat": _num(n.get("fat_100g")),
            }
            if not name or not _valid_per100g(per100g):
                continue
            serving = _num(prod.get("serving_quantity"))
            brand = _text(prod.get("brands")).split(",")[0].strip()
            items.append({
                "id": f"off:{prod.get('code')}", "source": "Open Food Facts",
                "name": name, "brand": brand or None,
                "per100g": {k: round(v, 1) for k, v in per100g.items()},
                "servingG": round(serving) if serving and 5 <= serving <= 1000 else 100,
            })
        except (AttributeError, TypeError, ValueError):
            continue  # one odd record must never break the whole search
    return items


def _search_usda(query: str) -> List[dict]:
    resp = requests.get(
        USDA_URL, timeout=(4, 8), headers={"User-Agent": USER_AGENT},
        params={
            "query": query, "pageSize": 15, "dataType": "Foundation,SR Legacy",
            "api_key": os.environ.get("USDA_API_KEY", "DEMO_KEY"),
        },
    )
    resp.raise_for_status()
    return parse_usda(resp.json())


def _get_with_retry(url: str, params: dict, tries: int = 2) -> dict:
    """Open Food Facts is a free community service and sometimes answers 503 when busy."""
    last = None
    for attempt in range(tries):
        try:
            resp = requests.get(url, params=params, timeout=(4, 8), headers={"User-Agent": USER_AGENT})
            resp.raise_for_status()
            return resp.json()
        except requests.RequestException as e:
            last = e
            if attempt + 1 < tries:
                time.sleep(0.7)
    raise last


def _search_off(query: str) -> List[dict]:
    fields = "code,product_name,brands,serving_quantity,nutriments"
    try:
        return parse_off(_get_with_retry(OFF_NEW_URL, {"q": query, "page_size": 20, "fields": fields}))
    except (requests.RequestException, ValueError) as e:
        logger.info("Open Food Facts new search failed (%s), trying the older endpoint", repr(e))
    return parse_off(_get_with_retry(OFF_URL, {
        "search_terms": query, "search_simple": 1, "action": "process", "json": 1,
        "page_size": 20, "fields": fields,
    }))


PROVIDERS = {"USDA": _search_usda, "Open Food Facts": _search_off}


def search_foods(query: str) -> dict:
    """Returns {"items": [...], "warnings": [...]}; results are cached briefly per query."""
    key = query.strip().lower()
    hit = _cache.get(key)
    if hit and time.monotonic() - hit[0] < CACHE_SECONDS:
        return hit[1]

    futures = {name: _POOL.submit(fn, query) for name, fn in PROVIDERS.items()}
    deadline = time.monotonic() + DEADLINE_SECONDS
    items, warnings = [], []
    for name, future in futures.items():
        try:
            items.extend(future.result(timeout=max(0.1, deadline - time.monotonic())))
        except (requests.RequestException, FutureTimeout, ValueError) as e:
            logger.warning("Food search via %s failed: %s", name, repr(e))
            warnings.append(f"{name} is not responding right now.")

    # Generic USDA foods first (clean data), then packaged products.
    items.sort(key=lambda i: 0 if i["source"] == "USDA" else 1)
    result = {"items": items, "warnings": warnings}
    if items and not warnings:
        _cache[key] = (time.monotonic(), result)
    return result
