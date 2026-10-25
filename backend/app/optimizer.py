"""
Ingredient-level macronutrient optimizer (FYP 2, Chapter 3).

Minimises the weighted, relative squared error between the recipe's nutrition and the
allocated meal target:

    Z(W) = sum_j  lambda_j * ((N_j(W) - A_j) / max(A_j, eps))^2   +   rho * sum_i ((W_i - B_i) / B_i)^2

N_j(W) is linear in the ingredient weights W (nutrition per 100 g x weight / 100), so Z is a
convex quadratic: the bounded solver (SciPy SLSQP) finds the global minimum and the answer is
reproducible (deterministic start at the original recipe, no random numbers).

The second term (rho, tiny by default) is a documented tie-breaker: when several weight
combinations hit the targets equally well it picks the one closest to the original recipe, which
keeps the dish's proportions and makes the result unique. Set rho = 0 to switch it off.
"""
from dataclasses import dataclass, field
from typing import Optional

import numpy as np
from scipy.optimize import minimize

from app.ingredient_data import NUTRIENTS

EPSILON = 1.0                 # keeps the division stable when a target is 0
ROUNDING_G = 1.0              # final weights are rounded to whole grams
TOLERANCE_PCT = 5.0           # a nutrient within +-5% of its target counts as "met"


@dataclass
class OptimizerConfig:
    lambdas: dict = field(default_factory=lambda: {"calories": 1.0, "protein": 1.0, "carbs": 1.0, "fat": 1.0})
    rho: float = 0.01
    epsilon: float = EPSILON
    tolerance_pct: float = TOLERANCE_PCT


class OptimizerError(ValueError):
    pass


def _nutrition(items, weights):
    return {k: float(sum(w / 100.0 * it["per100g"][k] for it, w in zip(items, weights))) for k in NUTRIENTS}


def objective_value(items, weights, allocated, cfg: Optional[OptimizerConfig] = None) -> float:
    """Z(W) for the given weights (exposed so tests can compute it independently)."""
    cfg = cfg or OptimizerConfig()
    n = _nutrition(items, weights)
    z = sum(cfg.lambdas[k] * ((n[k] - allocated[k]) / max(allocated[k], cfg.epsilon)) ** 2 for k in NUTRIENTS)
    z += cfg.rho * sum(((w - it["base"]) / it["base"]) ** 2 for it, w in zip(items, weights) if it["adjustable"])
    return float(z)


def _validate(items, allocated):
    if not items:
        raise OptimizerError("The recipe has no ingredients to optimise")
    for it in items:
        if it["base"] <= 0 or it["min"] < 0 or it["min"] > it["max"]:
            raise OptimizerError(f"Invalid weight limits for {it['name']}")
    for k in NUTRIENTS:
        v = allocated.get(k)
        if v is None or v < 0 or v != v:
            raise OptimizerError(f"Allocated {k} target must be a number >= 0")


def optimize(items: list, allocated: dict, cfg: Optional[OptimizerConfig] = None) -> dict:
    """
    items: [{name, base, min, max, adjustable, per100g{calories,protein,carbs,fat}, ...}]
    allocated: {calories, protein, carbs, fat} for THIS meal.
    """
    cfg = cfg or OptimizerConfig()
    _validate(items, allocated)

    base = np.array([it["base"] for it in items], dtype=float)
    lo = np.array([it["min"] for it in items], dtype=float)
    hi = np.array([it["max"] for it in items], dtype=float)
    adjustable = np.array([it["adjustable"] for it in items], dtype=bool)

    # Work in "multiples of the base weight" (x = W / B): all variables are about 1, which keeps
    # the solver well conditioned whether an ingredient weighs 6 g or 250 g.
    x0 = np.clip(np.ones_like(base), lo / base, hi / base)
    bounds = [(l / b, h / b) for l, h, b in zip(lo, hi, base)]

    def f(x):
        return objective_value(items, x * base, allocated, cfg)

    res = minimize(f, x0, method="SLSQP", bounds=bounds, options={"maxiter": 300, "ftol": 1e-12})
    x = np.clip(res.x if res.success or f(res.x) <= f(x0) else x0, [b[0] for b in bounds], [b[1] for b in bounds])
    x = np.where(adjustable, x, x0)

    raw = x * base
    rounded = np.clip(np.round(raw / ROUNDING_G) * ROUNDING_G, lo, hi)
    rounded = np.where(adjustable, rounded, base)

    nutrition = _nutrition(items, rounded)
    base_nutrition = _nutrition(items, base)

    comparison = {}
    for k in NUTRIENTS:
        diff = nutrition[k] - allocated[k]
        pct = (diff / allocated[k] * 100.0) if allocated[k] > 0 else None
        comparison[k] = {
            "target": round(allocated[k], 1), "recipe": round(nutrition[k], 1), "original": round(base_nutrition[k], 1),
            "difference": round(diff, 1), "differencePct": None if pct is None else round(pct, 1),
            "met": (abs(pct) <= cfg.tolerance_pct) if pct is not None else abs(diff) <= cfg.epsilon,
        }

    ingredients, limited = [], []
    for it, w, b in zip(items, rounded, base):
        at_min = it["adjustable"] and abs(w - it["min"]) < 0.5 and it["min"] < it["max"]
        at_max = it["adjustable"] and abs(w - it["max"]) < 0.5 and it["min"] < it["max"]
        if at_min or at_max:
            limited.append((it["name"], "minimum" if at_min else "maximum"))
        ingredients.append({
            "name": it["name"], "emoji": it.get("emoji", "🥗"), "unit": it["unit"],
            "originalAmount": round(float(b), 1), "optimizedAmount": float(w),
            "adjustable": bool(it["adjustable"]), "limit": "minimum" if at_min else ("maximum" if at_max else None),
            "nutrition": {k: round(float(w) / 100.0 * it["per100g"][k], 1) for k in NUTRIENTS},
        })

    missed = [k for k in NUTRIENTS if not comparison[k]["met"]]
    warnings = []
    if missed:
        names = {"calories": "Calories", "protein": "Protein", "carbs": "Carbs", "fat": "Fat"}
        for k in missed:
            c = comparison[k]
            direction = "above" if c["difference"] > 0 else "below"
            amount = f"{abs(c['differencePct'])}%" if c["differencePct"] is not None else f"{abs(c['difference'])}"
            warnings.append(f"{names[k]} is {amount} {direction} the target.")
        if limited:
            warnings.append("Some ingredients reached their limit: " + ", ".join(f"{n} ({w})" for n, w in limited) + ".")
        warnings.append("This is the closest recipe possible within the ingredient limits.")

    return {
        "status": "exact" if not missed else "closest",
        "method": "ingredient_optimization",
        "objective": round(objective_value(items, rounded, allocated, cfg), 6),
        "solver": {"name": "SLSQP", "converged": bool(res.success), "iterations": int(res.nit)},
        "ingredients": ingredients,
        "nutrition": {k: round(nutrition[k], 1) for k in NUTRIENTS},
        "comparison": comparison,
        "warnings": warnings,
    }


def optimize_uniform(recipe_name: str, per_serving: dict, allocated: dict, cfg: Optional[OptimizerConfig] = None,
                     min_factor: float = 0.5, max_factor: float = 2.5) -> dict:
    """
    Fallback for recipes without per-ingredient nutrition data (for example imported online
    recipes): only ONE portion multiplier can be chosen. The result is clearly labelled so it is
    never presented as ingredient-level optimisation.
    """
    pseudo = [{
        "name": recipe_name, "base": 100.0, "min": 100.0 * min_factor, "max": 100.0 * max_factor,
        "adjustable": True, "unit": "g", "per100g": {k: float(per_serving[k]) for k in NUTRIENTS},
    }]
    result = optimize(pseudo, allocated, cfg)
    result["factor"] = round(result["ingredients"][0]["optimizedAmount"] / 100.0, 2)
    result["method"] = "portion_scaling_fallback"
    return result
