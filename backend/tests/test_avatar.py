import base64
import io

from fastapi.testclient import TestClient
from PIL import Image

from app.main import app
from tests.helpers import new_user

client = TestClient(app)


def _img(size=(800, 500), fmt="PNG"):
    buf = io.BytesIO()
    Image.new("RGB", size, (200, 80, 40)).save(buf, fmt)
    return base64.b64encode(buf.getvalue()).decode()


def test_upload_resizes_to_small_square_and_can_be_removed():
    uid, h = new_user()
    r = client.put("/auth/avatar", headers=h, json={"imageBase64": _img()})
    assert r.status_code == 200
    b64 = r.json()["user"]["avatarB64"]
    out = Image.open(io.BytesIO(base64.b64decode(b64)))
    assert out.size == (256, 256) and out.format == "JPEG" and len(b64) < 60_000
    assert client.get("/auth/me", headers=h).json()["user"]["avatarB64"] == b64
    assert client.delete("/auth/avatar", headers=h).json()["user"]["avatarB64"] is None


def test_bad_uploads_rejected():
    uid, h = new_user()
    assert client.put("/auth/avatar", headers=h, json={"imageBase64": base64.b64encode(b"not an image").decode()}).status_code == 422
    assert client.put("/auth/avatar", headers=h, json={"imageBase64": _img((20, 20))}).status_code == 422
    assert client.put("/auth/avatar", headers=h, json={"imageBase64": ""}).status_code == 422
    assert client.put("/auth/avatar", json={"imageBase64": _img()}).status_code == 401


def test_coach_sees_client_photo_in_clients_chat_and_my_coach():
    coach, ch = new_user(role="coach")
    uid, h = new_user(coach_id=coach)
    b64 = client.put("/auth/avatar", headers=h, json={"imageBase64": _img()}).json()["user"]["avatarB64"]
    clients = client.get("/coach/clients", headers=ch).json()
    rows = clients if isinstance(clients, list) else clients.get("clients", [])
    assert any(c["id"] == uid and c["avatarB64"] == b64 for c in rows)
    assert client.get(f"/messages/{uid}", headers=ch).json()["client"]["avatarB64"] == b64
    cb = client.put("/auth/avatar", headers=ch, json={"imageBase64": _img()}).json()["user"]["avatarB64"]
    assert client.get("/auth/my-coach", headers=h).json()["coach"]["avatarB64"] == cb

