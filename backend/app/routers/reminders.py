"""
User alarms. Each reminder has a title and a time of day ("HH:MM", 24-hour, in the user's local time).
The app rings them (in-app alarm while it is open, and a scheduled notification on phones).
"""
import re
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel

from app.firebase import db
from app.auth import get_current_user
from app.schemas import ReminderToggleRequest, ReminderBulkSaveRequest

router = APIRouter(prefix="/reminders", tags=["reminders"])

MAX_REMINDERS = 20
_HHMM = re.compile(r"^([01]\d|2[0-3]):([0-5]\d)$")
_LABEL = re.compile(r"^\s*(\d{1,2}):(\d{2})\s*([AaPp][Mm])\s*$")


class ReminderCreate(BaseModel):
    title: str
    time: str                      # "HH:MM", 24-hour
    icon: Optional[str] = "⏰"
    subtitle: Optional[str] = ""


class ReminderUpdate(BaseModel):
    title: Optional[str] = None
    time: Optional[str] = None
    enabled: Optional[bool] = None
    icon: Optional[str] = None


def label_to_hhmm(label: str) -> Optional[str]:
    """'6:00 AM' -> '06:00'. Returns None for labels that are not a clock time (for example 'Every 2 hrs')."""
    m = _LABEL.match(label or "")
    if not m:
        return None
    h, minute, ap = int(m.group(1)), int(m.group(2)), m.group(3).lower()
    if not (1 <= h <= 12 and 0 <= minute <= 59):
        return None
    h = h % 12 + (12 if ap == "pm" else 0)
    return f"{h:02d}:{minute:02d}"


def hhmm_to_label(hhmm: str) -> str:
    """'06:00' -> '6:00 AM' (the format the phone scheduler understands)."""
    h, m = int(hhmm[:2]), int(hhmm[3:])
    return f"{(h % 12) or 12}:{m:02d} {'AM' if h < 12 else 'PM'}"


def _col(uid: str):
    return db.collection("users").document(uid).collection("reminders")


def _check_time(value: str) -> str:
    if not _HHMM.match(value or ""):
        raise HTTPException(status_code=422, detail="Time must look like 07:30 (24-hour)")
    return value


def _check_title(value: str) -> str:
    value = (value or "").strip()
    if not 1 <= len(value) <= 40:
        raise HTTPException(status_code=422, detail="Name must be 1 to 40 characters")
    return value


@router.get("")
def list_reminders(user: dict = Depends(get_current_user)):
    col = _col(user["uid"])
    items = []
    for snap in col.stream():
        r = snap.to_dict()
        if not r.get("time"):
            # Older reminders only had a text label. Convert once; labels that are not a clock time get a sensible default.
            r["time"] = label_to_hhmm(r.get("timeLabel", "")) or "10:00"
            r["timeLabel"] = hhmm_to_label(r["time"])
            col.document(snap.id).update({"time": r["time"], "timeLabel": r["timeLabel"]})
        r["id"] = snap.id
        items.append(r)
    items.sort(key=lambda r: (r["time"], r.get("title", "")))
    return {"reminders": items}


@router.post("", status_code=201)
def create_reminder(payload: ReminderCreate, user: dict = Depends(get_current_user)):
    col = _col(user["uid"])
    if len(list(col.stream())) >= MAX_REMINDERS:
        raise HTTPException(status_code=409, detail=f"You can have up to {MAX_REMINDERS} alarms")
    title, time = _check_title(payload.title), _check_time(payload.time)
    _, ref = col.add({
        "title": title, "time": time, "timeLabel": hhmm_to_label(time), "icon": payload.icon or "⏰",
        "subtitle": (payload.subtitle or "").strip()[:80], "enabled": True, "sortOrder": 0,
    })
    return {"id": ref.id, "time": time, "timeLabel": hhmm_to_label(time)}


@router.put("/{reminder_id}")
def update_reminder(reminder_id: str, payload: ReminderUpdate, user: dict = Depends(get_current_user)):
    doc = _col(user["uid"]).document(reminder_id)
    if not doc.get().exists:
        raise HTTPException(status_code=404, detail="Alarm not found")
    changes = {}
    if payload.title is not None:
        changes["title"] = _check_title(payload.title)
    if payload.time is not None:
        changes["time"] = _check_time(payload.time)
        changes["timeLabel"] = hhmm_to_label(payload.time)
    if payload.enabled is not None:
        changes["enabled"] = payload.enabled
    if payload.icon is not None:
        changes["icon"] = payload.icon
    if not changes:
        raise HTTPException(status_code=422, detail="Nothing to change")
    doc.update(changes)
    return {"ok": True, **changes}


@router.delete("/{reminder_id}", status_code=204)
def delete_reminder(reminder_id: str, user: dict = Depends(get_current_user)):
    doc = _col(user["uid"]).document(reminder_id)
    if not doc.get().exists:
        raise HTTPException(status_code=404, detail="Alarm not found")
    doc.delete()


@router.patch("/{reminder_id}")
def toggle_reminder(reminder_id: str, payload: ReminderToggleRequest, user: dict = Depends(get_current_user)):
    doc = _col(user["uid"]).document(reminder_id)
    if not doc.get().exists:
        raise HTTPException(status_code=404, detail="Reminder not found")
    doc.update({"enabled": payload.enabled})
    return {"ok": True}


@router.post("/save")
def bulk_save(payload: ReminderBulkSaveRequest, user: dict = Depends(get_current_user)):
    col = _col(user["uid"])
    for r in payload.reminders:
        doc = col.document(r["id"])
        if doc.get().exists:
            doc.update({"enabled": bool(r["enabled"])})
    return {"ok": True}
