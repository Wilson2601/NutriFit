import pytest
from fastapi.testclient import TestClient

from app import evaluation as ev
from app.main import app
from tests.helpers import new_user

client = TestClient(app)


def test_sus_known_reference_scores():
    assert ev.sus_score([5, 1, 5, 1, 5, 1, 5, 1, 5, 1]) == 100.0     # best possible
    assert ev.sus_score([1, 5, 1, 5, 1, 5, 1, 5, 1, 5]) == 0.0       # worst possible
    assert ev.sus_score([3] * 10) == 50.0
    assert ev.sus_score([4, 2, 4, 2, 4, 2, 4, 2, 4, 2]) == 75.0      # (3*5 + 3*5) * 2.5


def test_sus_rejects_bad_answers():
    for bad in ([3] * 9, [3] * 11, [0] + [3] * 9, [6] + [3] * 9, [True] + [3] * 9, ["a"] * 10):
        with pytest.raises(ev.EvaluationError):
            ev.sus_score(bad)


def test_satisfaction_and_task_completion():
    assert ev.satisfaction_score([5, 4, 3, 4, 2, 5]) == {"mean": 3.83, "agreePct": 66.7}
    r = ev.task_completion([{"taskId": "T1", "success": True}, {"taskId": "T1", "success": False}, {"taskId": "T2", "success": True}])
    assert r["rate"] == pytest.approx(66.7, abs=0.1) and r["perTask"]["T1"]["rate"] == 50.0
    assert ev.task_completion([])["rate"] is None


def test_summary_is_empty_without_real_data_and_endpoints_record_results():
    coach, ch = new_user("coach")
    user, uh = new_user()
    assert client.get("/evaluation/summary", headers=uh).status_code == 403
    r = client.post("/evaluation/sus", headers=uh, json={"participantId": "P1", "responses": [4, 2, 4, 2, 4, 2, 4, 2, 4, 2]})
    assert r.json()["score"] == 75.0
    assert client.post("/evaluation/sus", headers=uh, json={"participantId": "P1", "responses": [9] * 10}).status_code == 422
    assert client.post("/evaluation/task", headers=uh, json={"participantId": "P1", "taskId": "T3", "success": True, "seconds": 41}).status_code == 201
    assert client.post("/evaluation/task", headers=uh, json={"participantId": "P1", "taskId": "T99", "success": True}).status_code == 422
    s = client.get("/evaluation/summary", headers=ch).json()
    assert s["participantsSUS"] >= 1 and s["tasks"]["attempts"] >= 1
