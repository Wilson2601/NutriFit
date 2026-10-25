import base64
import io
import random
from datetime import datetime, timedelta, timezone

from fastapi.testclient import TestClient
from PIL import Image

from app.main import app
from app.firebase import db

client = TestClient(app)


def _uid(email):
    return next(s.id for s in db.collection("users").stream() if s.to_dict().get("email") == email)


def _h(email):
    return {"Authorization": f"Bearer fakeuid:{_uid(email)}"}


def _jpeg(seed=1, size=(400, 400), flat=None) -> str:
    rnd = random.Random(seed)
    img = Image.new("RGB", size, flat or (0, 0, 0))
    if flat is None:
        px = img.load()
        for x in range(size[0]):
            for y in range(size[1]):
                px[x, y] = (rnd.randint(40, 220), rnd.randint(40, 220), rnd.randint(40, 220))
    buf = io.BytesIO()
    img.save(buf, "JPEG")
    return base64.b64encode(buf.getvalue()).decode()


def _log_meal(email):
    snap = next(s for s in db.collection("recipes").stream() if s.to_dict().get("nutritionComplete"))
    ings = [{"name": i["name"], "amount": i["baseAmount"]} for i in snap.to_dict()["ingredients"]]
    r = client.post("/meals/consume", json={"recipeId": snap.id, "mealType": "Lunch", "ingredients": ings}, headers=_h(email))
    assert r.status_code == 201
    return r.json()["id"]


def _now():
    return datetime.now(timezone.utc).isoformat()


EMAIL = "sara@example.com"


def test_gallery_source_is_rejected():
    meal = _log_meal(EMAIL)
    r = client.post("/missions/photo", headers=_h(EMAIL),
                    json={"mealLogId": meal, "imageBase64": _jpeg(2), "source": "gallery"})
    assert r.status_code == 400


def test_stale_photo_is_rejected():
    meal = _log_meal(EMAIL)
    old = (datetime.now(timezone.utc) - timedelta(hours=2)).isoformat()
    r = client.post("/missions/photo", headers=_h(EMAIL),
                    json={"mealLogId": meal, "imageBase64": _jpeg(3), "capturedAt": old})
    assert r.status_code == 400


def test_blank_photo_is_not_accepted():
    meal = _log_meal(EMAIL)
    r = client.post("/missions/photo", headers=_h(EMAIL),
                    json={"mealLogId": meal, "imageBase64": _jpeg(flat=(128, 128, 128)), "capturedAt": _now()})
    assert r.status_code == 201 and r.json()["accepted"] is False


def test_garbage_bytes_rejected():
    meal = _log_meal(EMAIL)
    r = client.post("/missions/photo", headers=_h(EMAIL),
                    json={"mealLogId": meal, "imageBase64": base64.b64encode(b"not an image").decode()})
    assert r.status_code == 422


def test_good_photo_accepted_and_duplicate_blocked():
    meal = _log_meal(EMAIL)
    img = _jpeg(10)
    r = client.post("/missions/photo", headers=_h(EMAIL), json={"mealLogId": meal, "imageBase64": img, "capturedAt": _now()})
    assert r.status_code == 201 and r.json()["accepted"] is True
    assert any(m["id"] == meal and m["hasPhoto"] for m in r.json()["mission"]["meals"])

    # Same meal again -> conflict
    r2 = client.post("/missions/photo", headers=_h(EMAIL), json={"mealLogId": meal, "imageBase64": _jpeg(11)})
    assert r2.status_code == 409

    # Same picture for a different meal -> rejected as reused
    meal2 = _log_meal(EMAIL)
    r3 = client.post("/missions/photo", headers=_h(EMAIL), json={"mealLogId": meal2, "imageBase64": img, "capturedAt": _now()})
    assert r3.json()["accepted"] is False


def test_mission_state_has_three_criteria_and_coach_sees_it():
    m = client.get("/missions/today", headers=_h(EMAIL)).json()
    assert [c["key"] for c in m["criteria"]] == ["photos", "calories", "protein"]
    prog = client.get(f"/coach/clients/{_uid(EMAIL)}/progress", headers=_h("wilson@nutrifit.my")).json()
    assert "passed" in prog["todayMission"]


def test_mission_fails_without_photos():
    m = client.get("/missions/today", headers=_h("raj@example.com")).json()
    assert m["passed"] is False


def test_ai_food_check_rejects_non_food_and_wrong_dish(monkeypatch):
    from app import food_vision
    monkeypatch.setenv("GEMINI_API_KEY", "test")
    meal = _log_meal(EMAIL)

    monkeypatch.setattr(food_vision, "check_food_photo",
                        lambda b64, name: {"isFood": False, "matchesDish": False, "confidence": 0.9, "description": "a cat"})
    r = client.post("/missions/photo", headers=_h(EMAIL), json={"mealLogId": meal, "imageBase64": _jpeg(40), "capturedAt": _now()})
    assert r.json()["accepted"] is False and "meal" in r.json()["reasons"][0]

    monkeypatch.setattr(food_vision, "check_food_photo",
                        lambda b64, name: {"isFood": True, "matchesDish": False, "confidence": 0.8, "description": "pizza"})
    r = client.post("/missions/photo", headers=_h(EMAIL), json={"mealLogId": meal, "imageBase64": _jpeg(41), "capturedAt": _now()})
    assert r.json()["accepted"] is False and "doesn't look like" in r.json()["reasons"][0]

    monkeypatch.setattr(food_vision, "check_food_photo",
                        lambda b64, name: {"isFood": True, "matchesDish": True, "confidence": 0.9, "description": "omelette"})
    r = client.post("/missions/photo", headers=_h(EMAIL), json={"mealLogId": meal, "imageBase64": _jpeg(42), "capturedAt": _now()})
    assert r.json()["accepted"] is True


def test_ai_food_check_outage_blocks_instead_of_approving(monkeypatch):
    from app import food_vision
    monkeypatch.setenv("GEMINI_API_KEY", "test")
    meal = _log_meal(EMAIL)

    def boom(b64, name):
        raise food_vision.FoodCheckUnavailable("down")
    monkeypatch.setattr(food_vision, "check_food_photo", boom)
    r = client.post("/missions/photo", headers=_h(EMAIL), json={"mealLogId": meal, "imageBase64": _jpeg(50), "capturedAt": _now()})
    assert r.status_code == 503
