"""
Sends push notifications via Firebase Cloud Messaging when real Firebase is
configured. In fake/dev mode (no service account key), this safely no-ops so
local development never breaks on a missing FCM setup.
"""
import logging
from datetime import datetime, timezone
from app.firebase import db, is_using_real_firebase

logger = logging.getLogger("nutrifit")

# Which notification preference switch controls which kind of push.
PREF_FOR_TYPE = {"targets_updated": "targets", "coach_note": "notes", "chat": "chat", "mission_passed": "mission", "meal_logged": "mission"}


def _allowed_by_prefs(profile: dict, data: dict = None) -> bool:
    prefs = profile.get("notifPrefs", {})
    if prefs.get("push") is False:
        return False
    key = PREF_FOR_TYPE.get((data or {}).get("type"))
    return not (key and prefs.get(key) is False)


def store_notification(uid: str, title: str, body: str, data: dict = None) -> None:
    """Keeps an in-app copy so the app can show a banner / bell list even when phone push is blocked."""
    try:
        snap = db.collection("users").document(uid).get()
        if not snap.exists:
            return
        prefs = snap.to_dict().get("notifPrefs", {})
        key = PREF_FOR_TYPE.get((data or {}).get("type"))
        if key and prefs.get(key) is False:
            return
        db.collection("users").document(uid).collection("notifications").add({
            "title": title, "body": body, "type": (data or {}).get("type", "info"),
            "data": {k: str(v) for k, v in (data or {}).items()},
            "createdAt": datetime.now(timezone.utc).isoformat(), "read": False,
        })
    except Exception as e:  # never break the request that triggered the notification
        logger.warning("Could not store notification for %s: %s", uid, e)


def send_push_notification(uid: str, title: str, body: str, data: dict = None) -> bool:
    """
    Looks up the user's registered FCM device token and sends them a push.
    Returns True if a send was attempted (regardless of delivery success),
    False if skipped (fake mode, or the user has no registered token).
    """
    store_notification(uid, title, body, data)
    if not is_using_real_firebase():
        logger.info("Fake mode — would have sent push to %s: %s / %s", uid, title, body)
        return False

    snap = db.collection("users").document(uid).get()
    if not snap.exists:
        return False
    profile = snap.to_dict()
    if not _allowed_by_prefs(profile, data):
        return False
    token = profile.get("fcmToken")
    if not token:
        return False

    from firebase_admin import messaging

    message = messaging.Message(
        notification=messaging.Notification(title=title, body=body),
        data={k: str(v) for k, v in (data or {}).items()},
        token=token,
    )
    try:
        messaging.send(message)
        return True
    except Exception as e:
        # A stale/invalid token shouldn't break the calling request (e.g. a coach
        # saving a client's targets should succeed even if that client's push fails).
        logger.warning("Push notification to %s failed: %s", uid, e)
        return False
