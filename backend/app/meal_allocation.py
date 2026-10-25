"""
Meal target allocation: how much of today's REMAINING nutrition this meal should aim for.

    R_j = max(0, T_j - I_j)                     remaining daily target (I_j = confirmed intake only)
    A_j = min( f * R_j ,  cap_type * T_j )      allocated target for the meal

  f         depends on the answer to "Will you have another meal today?"
              yes      -> only part of the remaining amount is used now, the rest is reserved
              not_sure -> a moderate part, without assuming this is the last meal
              no       -> all of the remaining amount, BUT never more than a realistic single meal
  cap_type  the largest share of the daily target one meal of this type may carry
            (stops a skipped breakfast from turning lunch into an unrealistic mega-meal)

No fixed three-meal schedule is assumed: if breakfast was skipped, R_j is simply still the
whole daily target. All numbers live in AllocationConfig, can be overridden with the
NUTRIFIT_ALLOCATION_JSON environment variable, and are covered by tests.
"""
import json
import os
from dataclasses import dataclass, field

NUTRIENTS = ("calories", "protein", "carbs", "fat")
MEAL_TYPES = ("Breakfast", "Lunch", "Dinner", "Supper", "Other")
FUTURE_MEAL = ("yes", "no", "not_sure")


@dataclass
class AllocationConfig:
    future_fraction: dict = field(default_factory=lambda: {"yes": 0.5, "not_sure": 0.7, "no": 1.0})
    meal_cap: dict = field(default_factory=lambda: {
        "Breakfast": 0.35, "Lunch": 0.40, "Dinner": 0.40, "Supper": 0.20, "Other": 0.25,
    })


def load_config() -> AllocationConfig:
    cfg = AllocationConfig()
    raw = os.environ.get("NUTRIFIT_ALLOCATION_JSON", "").strip()
    if raw:
        data = json.loads(raw)
        cfg.future_fraction.update(data.get("future_fraction", {}))
        cfg.meal_cap.update(data.get("meal_cap", {}))
    return cfg


class AllocationError(ValueError):
    pass


def remaining_targets(target: dict, consumed: dict) -> dict:
    """R_j = max(0, T_j - I_j) for the four components."""
    return {k: max(0.0, float(target[k]) - float(consumed.get(k, 0.0))) for k in NUTRIENTS}


def normalise_meal_type(value: str) -> str:
    v = (value or "").strip().title()
    if v not in MEAL_TYPES:
        raise AllocationError(f"Meal type must be one of: {', '.join(MEAL_TYPES)}")
    return v


def normalise_future(value: str) -> str:
    v = (value or "").strip().lower().replace(" ", "_").replace("-", "_")
    if v not in FUTURE_MEAL:
        raise AllocationError("Another meal today must be yes, no or not_sure")
    return v


def allocate(target: dict, consumed: dict, meal_type: str, future_meal: str, cfg: AllocationConfig = None) -> dict:
    """Returns {meal, remaining, allocated, reserved, notes}. All values are floats (g or kcal)."""
    cfg = cfg or load_config()
    meal_type, future_meal = normalise_meal_type(meal_type), normalise_future(future_meal)
    remaining = remaining_targets(target, consumed)
    f, cap = cfg.future_fraction[future_meal], cfg.meal_cap[meal_type]

    allocated, capped = {}, []
    for k in NUTRIENTS:
        wanted = f * remaining[k]
        limit = cap * float(target[k])
        allocated[k] = min(wanted, limit)
        if wanted > limit + 1e-9:
            capped.append(k)

    notes = []
    if all(remaining[k] <= 0 for k in NUTRIENTS):
        notes.append("Today's targets are already reached, so there is nothing left to allocate.")
    elif capped:
        notes.append("Part of what is left today is kept for later because one meal should stay a realistic size.")
    if future_meal == "yes":
        notes.append("Part of the remaining nutrition is reserved for your next meal.")

    return {
        "mealType": meal_type, "futureMeal": future_meal,
        "factor": f, "capShare": cap,
        "remaining": {k: round(remaining[k], 1) for k in NUTRIENTS},
        "allocated": {k: round(allocated[k], 1) for k in NUTRIENTS},
        "reserved": {k: round(remaining[k] - allocated[k], 1) for k in NUTRIENTS},
        "notes": notes,
    }
