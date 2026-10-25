"""In-app notification feed (works for clients and coaches, independent of phone/browser push permission)."""
from fastapi import APIRouter, Depends, Query
from pydantic import BaseModel

from app.auth import get_current_user
from app.firebase import db

router = APIRouter(prefix="/notifications", tags=["notifications"])


class ReadRequest(BaseModel):
    ids: list[str] | None = None  # None = mark everything as read


def _col(uid: str):
    return db.collection("users").document(uid).collection("notifications")


@router.get("")
def list_notifications(limit: int = Query(30, ge=1, le=100), user: dict = Depends(get_current_user)):
    rows = [{**s.to_dict(), "id": s.id} for s in _col(user["uid"]).stream()]
    rows.sort(key=lambda r: r.get("createdAt", ""), reverse=True)
    return {"unread": sum(1 for r in rows if not r.get("read")), "items": rows[:limit]}


@router.post("/read")
def mark_read(payload: ReadRequest, user: dict = Depends(get_current_user)):
    changed = 0
    for s in list(_col(user["uid"]).stream()):
        if (payload.ids is None or s.id in payload.ids) and not s.to_dict().get("read"):
            _col(user["uid"]).document(s.id).update({"read": True})
            changed += 1
    return {"updated": changed}
