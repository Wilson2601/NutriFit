"""Daily tracking, planned vs consumed, adherence, coach view and regression checks."""
import pytest
from fastapi.testclient import TestClient

from app.main import app
from app.firebase import db
from tests.helpers import TARGET, add_log, add_target, new_user

client = TestClient(app)


def _recipe():
    snap = next(s for s in db.collection("recipes").stream() if s.to_dict().get("nutritionComplete"))
    return snap.id, snap.to_dict()


def _weights(r, factor=1.0):
    return [{"name": i["name"], "amount": round(i["baseAmount"] * factor, 1)} for i in r["ingredients"]]


# ---------- remaining targets + planned vs consumed ----------

def test_optimize_preview_does_not_change_totals():
    uid, h = new_user(target=TARGET)
    rid, _ = _recipe()
    r = client.post(f"/recipes/{rid}/optimize", json={"mealType": "Lunch", "futureMeal": "yes"}, headers=h)
    assert r.status_code == 200
    body = r.json()
    assert body["result"]["method"] == "ingredient_optimization" and body["allocation"]["mealType"] == "Lunch"
    s = client.get("/nutrition/summary", headers=h).json()
    assert s["consumed"]["calories"] == 0 and s["remaining"]["calories"] == 2000 and s["mealCount"] == 0


def test_planned_meal_is_not_counted_until_confirmed_and_confirm_updates_remaining():
    uid, h = new_user(target=TARGET)
    rid, r = _recipe()
    plan = client.post("/meals/plan", headers=h, json={"recipeId": rid, "mealType": "Dinner", "ingredients": _weights(r)})
    assert plan.status_code == 201
    assert client.get("/nutrition/summary", headers=h).json()["consumed"]["calories"] == 0
    assert len(client.get("/meals/planned", headers=h).json()["planned"]) == 1

    eaten = client.post("/meals/consume", headers=h, json={
        "recipeId": rid, "mealType": "Dinner", "ingredients": _weights(r), "plannedId": plan.json()["id"], "requestId": "r1"})
    assert eaten.status_code == 201
    s = client.get("/nutrition/summary", headers=h).json()
    assert s["consumed"]["calories"] == eaten.json()["macros"]["calories"] > 0
    assert s["remaining"]["calories"] == pytest.approx(2000 - s["consumed"]["calories"], abs=0.1)
    assert client.get("/meals/planned", headers=h).json()["planned"] == []


def test_duplicate_submission_is_ignored():
    uid, h = new_user(target=TARGET)
    rid, r = _recipe()
    body = {"recipeId": rid, "mealType": "Lunch", "ingredients": _weights(r), "requestId": "same-1"}
    a = client.post("/meals/consume", headers=h, json=body)
    b = client.post("/meals/consume", headers=h, json=body)
    assert a.status_code == 201 and b.json()["duplicate"] is True and b.json()["id"] == a.json()["id"]
    assert client.get("/nutrition/summary", headers=h).json()["mealCount"] == 1


def test_edit_and_delete_recalculate_totals():
    uid, h = new_user(target=TARGET)
    rid, r = _recipe()
    m = client.post("/meals/consume", headers=h, json={"recipeId": rid, "mealType": "Lunch", "ingredients": _weights(r)}).json()
    before = client.get("/nutrition/summary", headers=h).json()["consumed"]["calories"]
    assert client.put(f"/meals/{m['id']}", headers=h, json={"ingredients": _weights(r, 2.0)}).status_code == 200
    after = client.get("/nutrition/summary", headers=h).json()["consumed"]["calories"]
    assert after == pytest.approx(before * 2, rel=0.01)
    assert client.delete(f"/meals/{m['id']}", headers=h).status_code == 204
    assert client.get("/nutrition/summary", headers=h).json()["consumed"]["calories"] == 0


def test_over_target_stays_visible_while_remaining_is_zero():
    uid, h = new_user(target=TARGET)
    add_log(uid, 0, 2400, 170, 250, 80)
    c = client.get("/nutrition/summary", headers=h).json()["components"]
    assert c["calories"]["remaining"] == 0 and c["calories"]["over"] == 400 and c["calories"]["state"] == "above"


def test_client_cannot_send_macros_or_foreign_ingredients_or_bad_weights():
    uid, h = new_user(target=TARGET)
    rid, r = _recipe()
    bad = client.post("/meals/consume", headers=h, json={"recipeId": rid, "ingredients": [{"name": "Moon Cheese", "amount": 5}]})
    assert bad.status_code == 422
    neg = client.post("/meals/consume", headers=h, json={"recipeId": rid, "ingredients": [{"name": r["ingredients"][0]["name"], "amount": -4}]})
    assert neg.status_code == 422
    assert client.post("/meals/consume", headers=h, json={"recipeId": "nope", "ingredients": []}).status_code == 404
    assert client.post(f"/recipes/{rid}/optimize", headers=h, json={"mealType": "Brunch", "futureMeal": "yes"}).status_code == 422


def test_target_change_applies_to_next_optimisation_but_history_keeps_old_target():
    uid, h = new_user(target={"calories": 1500, "proteinG": 100, "carbsG": 150, "fatG": 50}, target_days_ago=10)
    add_target(uid, {"calories": 2500, "proteinG": 180, "carbsG": 300, "fatG": 80}, 0)
    add_log(uid, 3, 1500, 100, 150, 50)
    old_day = client.get("/nutrition/summary", params={"date": __import__("app.timeutil", fromlist=["x"]).days_ago_str(3)}, headers=h).json()
    assert old_day["target"]["calories"] == 1500 and old_day["adherent"] is True
    assert client.get("/nutrition/summary", headers=h).json()["target"]["calories"] == 2500


# ---------- adherence ----------

def _day(uid, offset, pct):
    add_log(uid, offset, 2000 * pct, 150 * pct, 200 * pct, 60 * pct)


def test_adherence_thresholds_boundaries():
    uid, h = new_user(target=TARGET)
    _day(uid, 1, 0.85)      # calories exactly at the lower bound -> within
    _day(uid, 2, 0.84)      # just below -> not adherent
    _day(uid, 3, 1.15)      # upper bound -> within
    _day(uid, 4, 1.16)      # above
    rep = client.get("/nutrition/adherence", params={"days": 4}, headers=h).json()
    flags = [d["adherent"] for d in rep["history"]]          # oldest first: day4, day3, day2, day1
    assert flags == [False, True, False, True]


def test_adherence_rate_and_no_record_days_are_separate():
    uid, h = new_user(target=TARGET)
    _day(uid, 1, 1.0); _day(uid, 2, 1.0); _day(uid, 3, 0.5)     # days 4-7 have no records
    rep = client.get("/nutrition/adherence", params={"days": 7}, headers=h).json()
    assert rep["observationDays"] == 7 and rep["adherentDays"] == 2 and rep["loggedDays"] == 3 and rep["noRecordDays"] == 4
    assert rep["adherenceRate"] == pytest.approx(2 / 7 * 100, abs=0.1)
    assert rep["adherenceRateOfLoggedDays"] == pytest.approx(2 / 3 * 100, abs=0.1)
    assert rep["loggingCompleteness"] == pytest.approx(3 / 7 * 100, abs=0.1)
    assert all(d["status"] == "no_records" and d["adherent"] is False for d in rep["history"] if not d["hasRecords"])


def test_one_nutrient_out_of_range_breaks_adherence_and_planned_meals_never_count():
    uid, h = new_user(target=TARGET)
    add_log(uid, 1, 2000, 150, 200, 30)                   # fat at 50%
    add_log(uid, 2, 2000, 150, 200, 60, status="planned")  # planned only
    rep = client.get("/nutrition/adherence", params={"days": 2}, headers=h).json()
    assert [d["adherent"] for d in rep["history"]] == [False, False]
    assert rep["history"][1]["components"]["fat"]["state"] == "below"
    assert rep["history"][0]["hasRecords"] is False


def test_30_day_period_supported():
    uid, h = new_user(target=TARGET)
    assert client.get("/nutrition/adherence", params={"days": 30}, headers=h).json()["observationDays"] == 30


# ---------- coach + roles ----------

def test_coach_sees_only_own_client_with_unified_numbers_and_can_change_targets():
    coach, ch = new_user("coach")
    uid, uh = new_user(coach_id=coach, target=TARGET)
    other_coach, och = new_user("coach")
    _day(uid, 1, 1.0)
    p = client.get(f"/coach/clients/{uid}/progress", params={"days": 7}, headers=ch)
    assert p.status_code == 200
    body = p.json()
    assert body["adherence"]["adherentDays"] == 1 and body["adherence"]["loggedDays"] == 1
    assert body["today"]["components"]["protein"]["target"] == 150 and len(body["history"]) == 7
    assert client.get(f"/coach/clients/{uid}/progress", headers=och).status_code == 404       # not their client
    assert client.get(f"/coach/clients/{uid}/progress", headers=uh).status_code == 403        # user role blocked

    r = client.put(f"/coach/clients/{uid}/targets", headers=ch, json={"calories": 1800, "proteinG": 140, "carbsG": 180, "fatG": 55})
    assert r.status_code == 200
    assert client.get("/nutrition/summary", headers=uh).json()["target"]["calories"] == 1800


def test_regression_existing_features_still_work():
    uid, h = new_user(target=TARGET)
    assert client.get("/health").status_code == 200
    assert client.get("/recipes", headers=h).json()["recipes"]
    assert client.get("/targets/me", headers=h).json()["target"]["calories"] == 2000
    assert client.get("/progress/today", headers=h).status_code == 200
    assert client.get("/grocery", headers=h).status_code == 200
    assert client.get("/reminders", headers=h).status_code == 200
    assert client.get("/recipes").status_code == 401
    sug = client.get("/recipes/suggested", headers=h).json()
    assert sug["suggestions"] and all("matchPct" in s for s in sug["suggestions"])
    rid, _ = _recipe()
    assert client.post(f"/grocery/from-recipe/{rid}", headers=h).status_code == 201


def test_suggestions_prefer_recipes_that_fit_what_is_left():
    uid, h = new_user(target=TARGET)
    add_log(uid, 0, 1400, 40, 250, 70)            # lots of calories/carbs/fat eaten, little protein
    sug = client.get("/recipes/suggested", params={"mealType": "Dinner", "futureMeal": "no"}, headers=h).json()
    assert sug["remaining"]["protein"] == 110
    scores = [s["matchPct"] for s in sug["suggestions"]]
    assert scores == sorted(scores, reverse=True)


def test_grocery_clear_checked_and_all():
    uid, h = new_user(target=TARGET)
    ids = [client.post("/grocery", headers=h, json={"name": n, "amount": 10, "unit": "g"}).json()["id"] for n in ("A", "B", "C")]
    client.patch(f"/grocery/{ids[0]}", headers=h, json={"checked": True})
    client.patch(f"/grocery/{ids[1]}", headers=h, json={"checked": True})
    assert client.delete("/grocery", params={"scope": "checked"}, headers=h).json() == {"removed": 2}
    assert [i["name"] for i in client.get("/grocery", headers=h).json()["items"]] == ["C"]
    assert client.delete("/grocery", params={"scope": "all"}, headers=h).json() == {"removed": 1}
    assert client.get("/grocery", headers=h).json()["items"] == []
    assert client.delete("/grocery", params={"scope": "x"}, headers=h).status_code == 422


def test_plan_adds_to_grocery_shows_in_progress_and_can_be_opened_then_logged():
    uid, h = new_user(target=TARGET)
    rid, r = _recipe()
    plan = client.post("/meals/plan", headers=h, json={"recipeId": rid, "mealType": "Dinner", "ingredients": _weights(r)}).json()
    assert plan["groceryAdded"] == len(r["ingredients"])
    assert len(client.get("/grocery", headers=h).json()["items"]) == len(r["ingredients"])
    prog = client.get("/progress/today", headers=h).json()
    assert [p["id"] for p in prog["planned"]] == [plan["id"]] and prog["totals"]["calories"] == 0
    detail = client.get(f"/meals/planned/{plan['id']}", headers=h).json()
    assert detail["steps"] is not None and len(detail["ingredients"]) == len(r["ingredients"])
    assert client.get("/meals/planned/nope", headers=h).status_code == 404
    ings = [{"name": i["name"], "amount": i["amount"]} for i in detail["ingredients"]]
    ok = client.post("/meals/consume", headers=h, json={"recipeId": rid, "mealType": "Dinner", "ingredients": ings, "plannedId": plan["id"]})
    assert ok.status_code == 201
    prog = client.get("/progress/today", headers=h).json()
    assert prog["planned"] == [] and prog["totals"]["calories"] > 0


def test_coach_target_typos_are_rejected():
    coach, ch = new_user("coach")
    uid, _ = new_user(coach_id=coach, target=TARGET)
    bad = client.put(f"/coach/clients/{uid}/targets", headers=ch, json={"calories": 2500, "proteinG": 1500, "carbsG": 180, "fatG": 100})
    assert bad.status_code == 422 and "Protein" in bad.json()["detail"]


def test_coach_gets_in_app_notifications_for_chat_and_meals():
    from tests.helpers import new_user
    coach, ch = new_user(role="coach")
    uid, h = new_user(coach_id=coach)
    assert client.post(f"/messages/{uid}", headers=h, json={"text": "hello coach"}).status_code == 201
    r = client.get("/notifications", headers=ch).json()
    assert r["unread"] >= 1 and r["items"][0]["type"] == "chat" and r["items"][0]["body"] == "hello coach"
    assert client.post("/notifications/read", headers=ch, json={}).json()["updated"] >= 1
    assert client.get("/notifications", headers=ch).json()["unread"] == 0
    # the client does not see the coach's notifications
    assert client.get("/notifications", headers=h).json()["items"] == []
