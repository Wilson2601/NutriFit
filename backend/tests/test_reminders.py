from fastapi.testclient import TestClient

from app.firebase import db
from app.main import app
from app.routers.reminders import hhmm_to_label, label_to_hhmm
from tests.helpers import new_user

client = TestClient(app)


def test_time_conversions():
    assert label_to_hhmm("6:00 AM") == "06:00" and label_to_hhmm("12:00 AM") == "00:00"
    assert label_to_hhmm("12:30 PM") == "12:30" and label_to_hhmm("5:30 PM") == "17:30"
    assert label_to_hhmm("Every 2 hrs") is None and label_to_hhmm("13:00 PM") is None
    assert hhmm_to_label("00:05") == "12:05 AM" and hhmm_to_label("17:30") == "5:30 PM" and hhmm_to_label("12:00") == "12:00 PM"


def test_create_edit_toggle_delete_and_sorting():
    uid, h = new_user()
    a = client.post("/reminders", headers=h, json={"title": "Cook dinner", "time": "18:45"}).json()
    b = client.post("/reminders", headers=h, json={"title": "Wake up", "time": "06:30"}).json()
    items = client.get("/reminders", headers=h).json()["reminders"]
    assert [i["title"] for i in items] == ["Wake up", "Cook dinner"] and items[1]["timeLabel"] == "6:45 PM"

    assert client.put(f"/reminders/{a['id']}", headers=h, json={"time": "19:00", "title": "Dinner time"}).status_code == 200
    assert client.put(f"/reminders/{b['id']}", headers=h, json={"enabled": False}).json()["enabled"] is False
    items = {i["id"]: i for i in client.get("/reminders", headers=h).json()["reminders"]}
    assert items[a["id"]]["time"] == "19:00" and items[a["id"]]["title"] == "Dinner time" and items[b["id"]]["enabled"] is False

    assert client.delete(f"/reminders/{a['id']}", headers=h).status_code == 204
    assert client.delete(f"/reminders/{a['id']}", headers=h).status_code == 404
    assert len(client.get("/reminders", headers=h).json()["reminders"]) == 1


def test_validation_and_isolation():
    uid, h = new_user()
    other, oh = new_user()
    for bad in ("7:30", "24:00", "12:60", "", "noon"):
        assert client.post("/reminders", headers=h, json={"title": "x", "time": bad}).status_code == 422
    assert client.post("/reminders", headers=h, json={"title": "   ", "time": "07:30"}).status_code == 422
    rid = client.post("/reminders", headers=h, json={"title": "Mine", "time": "07:30"}).json()["id"]
    assert client.put(f"/reminders/{rid}", headers=oh, json={"enabled": False}).status_code == 404   # not someone else's alarm
    assert client.get("/reminders", headers=oh).json()["reminders"] == []


def test_old_label_only_reminders_are_converted():
    uid, h = new_user()
    db.collection("users").document(uid).collection("reminders").add({"title": "Old", "timeLabel": "2:00 PM", "enabled": True})
    db.collection("users").document(uid).collection("reminders").add({"title": "Odd", "timeLabel": "Every 2 hrs", "enabled": True})
    got = {r["title"]: r for r in client.get("/reminders", headers=h).json()["reminders"]}
    assert got["Old"]["time"] == "14:00" and got["Odd"]["time"] == "10:00" and got["Odd"]["timeLabel"] == "10:00 AM"


def test_alarm_limit():
    uid, h = new_user()
    for i in range(20):
        assert client.post("/reminders", headers=h, json={"title": f"A{i}", "time": "08:00"}).status_code == 201
    assert client.post("/reminders", headers=h, json={"title": "one more", "time": "08:00"}).status_code == 409
