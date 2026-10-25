import pytest

from app.meal_allocation import AllocationConfig, AllocationError, allocate, remaining_targets

T = {"calories": 2000, "protein": 150, "carbs": 200, "fat": 60}
NONE = {"calories": 0, "protein": 0, "carbs": 0, "fat": 0}
CFG = AllocationConfig()


def test_remaining_is_floored_at_zero_but_over_target_is_kept_elsewhere():
    r = remaining_targets(T, {"calories": 2300, "protein": 100, "carbs": 0, "fat": 60})
    assert r == {"calories": 0.0, "protein": 50.0, "carbs": 200.0, "fat": 0.0}


def test_skipped_breakfast_lunch_first_meal_uses_full_day_remaining():
    a = allocate(T, NONE, "Lunch", "yes", CFG)
    assert a["remaining"] == T
    assert a["allocated"]["calories"] == pytest.approx(2000 * 0.40)       # capped at the Lunch share
    assert a["reserved"]["calories"] == pytest.approx(2000 - 800)


def test_yes_reserves_part_for_later_meals():
    consumed = {"calories": 500, "protein": 30, "carbs": 60, "fat": 15}
    a = allocate(T, consumed, "Dinner", "yes", CFG)
    assert a["allocated"]["calories"] == pytest.approx(0.5 * 1500)


def test_not_sure_is_between_yes_and_no():
    consumed = {"calories": 1000, "protein": 80, "carbs": 100, "fat": 30}
    y = allocate(T, consumed, "Dinner", "yes", CFG)["allocated"]["calories"]
    n = allocate(T, consumed, "Dinner", "not_sure", CFG)["allocated"]["calories"]
    no = allocate(T, consumed, "Dinner", "no", CFG)["allocated"]["calories"]
    assert y < n < no


def test_no_still_enforces_realistic_portion_limit():
    a = allocate(T, NONE, "Supper", "no", CFG)
    assert a["allocated"]["calories"] == pytest.approx(2000 * 0.20)
    assert any("realistic" in n for n in a["notes"])


def test_no_gives_all_remaining_when_it_fits_one_meal():
    consumed = {"calories": 1500, "protein": 110, "carbs": 150, "fat": 45}
    a = allocate(T, consumed, "Dinner", "no", CFG)
    assert a["allocated"]["calories"] == 500


def test_everything_reached_allocates_nothing():
    a = allocate(T, {"calories": 2100, "protein": 160, "carbs": 210, "fat": 70}, "Dinner", "no", CFG)
    assert all(v == 0 for v in a["allocated"].values()) and a["notes"]


def test_config_is_adjustable():
    cfg = AllocationConfig(future_fraction={"yes": 0.25, "not_sure": 0.5, "no": 1.0})
    assert allocate(T, NONE, "Dinner", "yes", cfg)["allocated"]["calories"] == pytest.approx(500)


def test_bad_inputs():
    with pytest.raises(AllocationError):
        allocate(T, NONE, "Brunch", "yes", CFG)
    with pytest.raises(AllocationError):
        allocate(T, NONE, "Lunch", "maybe", CFG)
