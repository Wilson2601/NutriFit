"""
In-app chat between a coach and one of their clients.

Messages live in the subcollection users/{clientId}/messages, so a thread is
identified by the client's uid. Access rules:
  - a client may only read/write their own thread
  - a coach may only read/write threads of clients assigned to them
"""
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException

from app.auth import get_current_user
from app.firebase import db
from app.notifications import send_push_notification
from app.schemas import MessageRequest

router = APIRouter(prefix="/messages", tags=["messages"])

MAX_LEN = 1000


def _messages_ref(client_id: str):
    return db.collection("users").document(client_id).collection("messages")


def _authorize(user: dict, client_id: str) -> dict:
    """Returns the client's profile if `user` may access this thread, else raises."""
    snap = db.collection("users").document(client_id).get()
    if not snap.exists or snap.to_dict().get("role") != "user":
        raise HTTPException(status_code=404, detail="Conversation not found")
    client = snap.to_dict()
    if user["role"] == "user":
        if user["uid"] != client_id:
            raise HTTPException(status_code=403, detail="You can only open your own conversation")
    elif user["role"] == "coach":
        if client.get("coachId") != user["uid"]:
            raise HTTPException(status_code=404, detail="Client not found in your roster")
    else:
        raise HTTPException(status_code=403, detail="Not allowed")
    return client


def _load_thread(client_id: str) -> list:
    msgs = [{**m.to_dict(), "id": m.id} for m in _messages_ref(client_id).stream()]
    msgs.sort(key=lambda m: m.get("createdAt", ""))
    return msgs


@router.get("/threads")
def list_threads(user: dict = Depends(get_current_user)):
    """Coach inbox: one row per client with the latest message and unread count."""
    if user["role"] != "coach":
        raise HTTPException(status_code=403, detail="Requires coach role")
    rows = []
    for snap in db.collection("users").stream():
        c = snap.to_dict()
        if c.get("role") != "user" or c.get("coachId") != user["uid"]:
            continue
        thread = _load_thread(snap.id)
        last = thread[-1] if thread else None
        unread = sum(1 for m in thread if m["senderRole"] == "user" and user["uid"] not in m.get("readBy", []))
        rows.append({
            "clientId": snap.id, "name": c["name"], "initials": c.get("avatarInitials"), "avatarB64": c.get("avatarB64"),
            "lastMessage": last["text"] if last else None,
            "lastAt": last["createdAt"] if last else None,
            "unread": unread,
        })
    rows.sort(key=lambda r: r["lastAt"] or "", reverse=True)
    return {"threads": rows}


@router.get("/unread-count")
def unread_count(user: dict = Depends(get_current_user)):
    """Badge number: messages from the other side that this user has not read."""
    other = "coach" if user["role"] == "user" else "user"
    if user["role"] == "user":
        thread_ids = [user["uid"]]
    else:
        thread_ids = [s.id for s in db.collection("users").stream()
                      if s.to_dict().get("role") == "user" and s.to_dict().get("coachId") == user["uid"]]
    total = 0
    for cid in thread_ids:
        total += sum(1 for m in _load_thread(cid)
                     if m["senderRole"] == other and user["uid"] not in m.get("readBy", []))
    return {"unread": total}


@router.get("/{client_id}")
def get_thread(client_id: str, user: dict = Depends(get_current_user)):
    client = _authorize(user, client_id)
    thread = _load_thread(client_id)
    return {
        "client": {"id": client_id, "name": client["name"], "initials": client.get("avatarInitials"), "avatarB64": client.get("avatarB64")},
        "messages": thread,
    }


@router.post("/{client_id}", status_code=201)
def send_message(client_id: str, payload: MessageRequest, user: dict = Depends(get_current_user)):
    client = _authorize(user, client_id)
    text = payload.text.strip()
    if not text:
        raise HTTPException(status_code=422, detail="Message cannot be empty")
    if len(text) > MAX_LEN:
        raise HTTPException(status_code=422, detail=f"Message is too long (max {MAX_LEN} characters)")

    msg = {
        "senderId": user["uid"], "senderRole": user["role"], "senderName": user["name"],
        "text": text, "createdAt": datetime.now(timezone.utc).isoformat(),
        "readBy": [user["uid"]],
    }
    _, ref = _messages_ref(client_id).add(msg)

    # Notify the other side of the conversation.
    recipient = client.get("coachId") if user["role"] == "user" else client_id
    if recipient:
        send_push_notification(
            recipient, f"💬 {user['name']}", text[:100],
            data={"type": "chat", "clientId": client_id},
        )
    return {"message": {**msg, "id": ref.id}}


@router.post("/{client_id}/read")
def mark_read(client_id: str, user: dict = Depends(get_current_user)):
    _authorize(user, client_id)
    changed = 0
    for snap in _messages_ref(client_id).stream():
        m = snap.to_dict()
        readers = m.get("readBy", [])
        if user["uid"] not in readers:
            _messages_ref(client_id).document(snap.id).update({"readBy": readers + [user["uid"]]})
            changed += 1
    return {"marked": changed}
