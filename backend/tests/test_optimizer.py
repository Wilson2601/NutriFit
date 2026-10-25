"""Optimizer tests: independent reference values, constraints, infeasible targets, boundaries."""
import pytest

from app.ingredient_data import build_items, recipe_totals, valid_per100, enrich_recipe
from app.optimizer import OptimizerError, objective_value, optimize, optimize_uniform
from app.seed import _raw_recipes

BOWL = next(r for r in _raw_recipes() if r["name"] == "Grilled Chicken Bowl")
ITEMS = build_items(BOWL)["items"]


def test_recipe_totals_match_hand_calculation():
    # Calculated by hand from per-100g values (e.g. chicken 156 g x 165 kcal/100 g = 257.4 kcal).
    t = recipe_totals(ITEMS)
    assert t["calories"] == pytest.approx(526.16, abs=0.01)
    assert t["protein"] == pytest.approx(53.802, abs=0.001)
    assert t["carbs"] == pytest.approx(34.502, abs=0.001)
    assert t["fat"] == pytest.approx(18.288, abs=0.001)


def test_objective_matches_formula_by_hand():
    allocated = {"calories": 600, "protein": 50, "carbs": 40, "fat": 20}
    z = objective_value(ITEMS, [i["base"] for i in ITEMS], allocated)
    t = recipe_totals(ITEMS)
    expected = sum(((t[k] - allocated[k]) / allocated[k]) ** 2 for k in allocated)   # lambda = 1, rho term = 0 at base
    assert z == pytest.approx(expected, rel=1e-9)


def test_reachable_target_is_met_exactly_and_ingredients_differ_individually():
    # Target generated from known weights, so it is reachable within the limits.
    weights = [190, 150, 15, 110, 8, 6]
    target = recipe_totals(ITEMS, weights)
    res = optimize(ITEMS, target)
    assert res["status"] == "exact"
    for k, c in res["comparison"].items():
        assert abs(c["differencePct"]) <= 2.0, (k, c)
    factors = {round(i["optimizedAmount"] / i["originalAmount"], 2) for i in res["ingredients"] if i["adjustable"]}
    assert len(factors) > 1          # not one identical multiplier for every ingredient


def test_beats_uniform_scaling_on_macro_match():
    allocated = {"calories": 650, "protein": 70, "carbs": 45, "fat": 18}
    res = optimize(ITEMS, allocated)
    base = recipe_totals(ITEMS)
    s = allocated["calories"] / base["calories"]                    # old method: one factor from calories
    uniform_err = sum(abs(base[k] * s - allocated[k]) / allocated[k] for k in allocated)
    opt_err = sum(abs(res["nutrition"][k] - allocated[k]) / allocated[k] for k in allocated)
    assert opt_err < uniform_err


def test_limits_fixed_and_nonnegative_respected():
    res = optimize(ITEMS, {"calories": 900, "protein": 90, "carbs": 90, "fat": 30})
    for it, out in zip(ITEMS, res["ingredients"]):
        assert out["optimizedAmount"] >= 0
        assert it["min"] - 0.5 <= out["optimizedAmount"] <= it["max"] + 0.5
        if not it["adjustable"]:
            assert out["optimizedAmount"] == it["base"]           # soy sauce and garlic stay as written


def test_infeasible_target_returns_closest_with_explanation():
    res = optimize(ITEMS, {"calories": 5000, "protein": 400, "carbs": 500, "fat": 150})
    assert res["status"] == "closest"
    assert res["warnings"] and any("limit" in w for w in res["warnings"])
    assert any(i["limit"] == "maximum" for i in res["ingredients"])
    assert res["comparison"]["protein"]["difference"] < 0           # could not reach it
    for it, out in zip(ITEMS, res["ingredients"]):
        assert out["optimizedAmount"] <= it["max"] + 0.5


def test_zero_targets_are_stable():
    res = optimize(ITEMS, {"calories": 0, "protein": 0, "carbs": 0, "fat": 0})
    assert all(v == v for v in res["nutrition"].values())           # no NaN
    assert all(i["optimizedAmount"] <= i["originalAmount"] + 0.5 for i in res["ingredients"])
    res2 = optimize(ITEMS, {"calories": 500, "protein": 40, "carbs": 0, "fat": 15})
    assert res2["comparison"]["carbs"]["differencePct"] is None      # percent undefined for a zero target


def test_boundary_all_ingredients_at_minimum_for_tiny_target():
    res = optimize(ITEMS, {"calories": 50, "protein": 5, "carbs": 5, "fat": 2})
    assert res["status"] == "closest"
    for it, out in zip(ITEMS, res["ingredients"]):
        if it["adjustable"]:
            assert out["optimizedAmount"] == pytest.approx(it["min"], abs=1.0)


def test_reproducible_for_same_inputs():
    allocated = {"calories": 700, "protein": 55, "carbs": 70, "fat": 22}
    a, b = optimize(ITEMS, allocated), optimize(ITEMS, allocated)
    assert a["ingredients"] == b["ingredients"] and a["objective"] == b["objective"]


def test_invalid_inputs_rejected():
    with pytest.raises(OptimizerError):
        optimize([], {"calories": 1, "protein": 1, "carbs": 1, "fat": 1})
    with pytest.raises(OptimizerError):
        optimize(ITEMS, {"calories": -5, "protein": 1, "carbs": 1, "fat": 1})
    with pytest.raises(OptimizerError):
        optimize(ITEMS, {"calories": 1, "protein": 1, "carbs": 1})


def test_uniform_fallback_is_labelled_and_bounded():
    res = optimize_uniform("Imported dish", {"calories": 400, "protein": 30, "carbs": 40, "fat": 12},
                           {"calories": 800, "protein": 60, "carbs": 80, "fat": 24})
    assert res["method"] == "portion_scaling_fallback" and res["factor"] == pytest.approx(2.0, abs=0.05)


def test_missing_or_invalid_ingredient_data_is_reported_not_invented():
    recipe = {"ingredients": [
        {"name": "Mystery Powder", "baseAmount": 50, "unit": "g"},
        {"name": "Chicken Breast", "baseAmount": 100, "unit": "g"},
        {"name": "Rice", "baseAmount": 100, "unit": "g", "per100g": {"calories": 10, "protein": 50, "carbs": 50, "fat": 50}},
        {"name": "Oil", "baseAmount": -3, "unit": "g"},
        {"name": "Cheese", "baseAmount": 20, "unit": "cup"},
    ]}
    built = build_items(recipe)
    assert not built["complete"] and len(built["problems"]) == 4
    assert [i["name"] for i in built["items"]] == ["Chicken Breast"]
    assert enrich_recipe(recipe)["nutritionComplete"] is False


def test_reference_data_is_internally_consistent():
    from app.ingredient_data import REFERENCE
    for name, (kcal, p, c, f, _) in REFERENCE.items():
        assert valid_per100({"calories": kcal, "protein": p, "carbs": c, "fat": f}), name


def test_all_builtin_recipes_are_complete_and_totals_consistent():
    for r in _raw_recipes():
        e = enrich_recipe(r)
        assert e["nutritionComplete"], r["name"]
        t = recipe_totals(build_items(r)["items"])
        assert e["baseCalories"] == round(t["calories"]) and "refDailyCalories" not in e
        assert abs(e["baseCalories"] - (4 * e["baseProtein"] + 4 * e["baseCarbs"] + 9 * e["baseFat"])) <= 0.12 * e["baseCalories"] + 15
