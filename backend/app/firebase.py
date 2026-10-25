"""
Initializes Firebase Admin (Firestore + Auth) if a real service account key is
configured, otherwise falls back to the in-memory FakeFirestoreClient so the app
can run locally without a Firebase project. Everything else in the app imports
`db` and `verify_token` from here and never needs to know which mode is active.
"""
import os
import logging

logger = logging.getLogger("nutrifit")

SERVICE_ACCOUNT_PATH = os.environ.get("FIREBASE_SERVICE_ACCOUNT", "serviceAccountKey.json")
DEV_MODE = os.environ.get("DEV_MODE", "true").lower() == "true"

# On a hosting service there is no key file; the whole JSON is passed as an
# environment variable instead (FIREBASE_SERVICE_ACCOUNT_JSON).
SERVICE_ACCOUNT_JSON = os.environ.get("FIREBASE_SERVICE_ACCOUNT_JSON", "").strip()

_using_real_firebase = False

if SERVICE_ACCOUNT_JSON or os.path.exists(SERVICE_ACCOUNT_PATH):
    import firebase_admin
    from firebase_admin import credentials, firestore, auth as fb_auth

    if SERVICE_ACCOUNT_JSON:
        import json
        cred = credentials.Certificate(json.loads(SERVICE_ACCOUNT_JSON))
        source = "FIREBASE_SERVICE_ACCOUNT_JSON"
    else:
        cred = credentials.Certificate(SERVICE_ACCOUNT_PATH)
        source = SERVICE_ACCOUNT_PATH
    firebase_admin.initialize_app(cred)
    db = firestore.client()
    _using_real_firebase = True
    logger.info("Connected to real Firebase project using %s", source)

    def verify_token(id_token: str) -> dict:
        """Returns the decoded token (contains at least 'uid') or raises on invalid token."""
        return fb_auth.verify_id_token(id_token)

    def create_firebase_user(email: str, password: str, display_name: str) -> str:
        user = fb_auth.create_user(email=email, password=password, display_name=display_name)
        return user.uid

    def delete_firebase_user(uid: str) -> None:
        try:
            fb_auth.delete_user(uid)
        except Exception:
            pass  # already gone, or never existed — fine either way

else:
    from app.fake_firestore import FakeFirestoreClient

    db = FakeFirestoreClient()
    logger.warning(
        "No %s found — running against an in-memory fake Firestore. "
        "This is fine for local development, but data will NOT persist between "
        "server restarts and this is NOT connected to a real Firebase project. "
        "Add your service account key to enable real Firebase.",
        SERVICE_ACCOUNT_PATH,
    )

    # In fake mode there's no real Firebase Auth to talk to, so tokens are simply
    # "fakeuid:<uid>" strings minted by our own /auth/register + /auth/login endpoints
    # below. DEV_MODE must be true for this path to be reachable at all.
    def verify_token(id_token: str) -> dict:
        if not DEV_MODE:
            raise PermissionError("Fake auth tokens are only accepted when DEV_MODE=true")
        if not id_token.startswith("fakeuid:"):
            raise ValueError("Invalid fake token")
        return {"uid": id_token.split(":", 1)[1]}

    def create_firebase_user(email: str, password: str, display_name: str) -> str:
        import uuid
        return f"dev_{uuid.uuid4().hex[:20]}"

    def delete_firebase_user(uid: str) -> None:
        pass  # fake mode has no separate auth store to clean up


def is_using_real_firebase() -> bool:
    return _using_real_firebase
