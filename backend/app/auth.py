from fastapi import Depends, HTTPException, Header
from app.firebase import db, verify_token


def get_current_user(authorization: str = Header(None)) -> dict:
    """Verifies the Bearer token and returns the caller's Firestore user profile (with 'uid' set)."""
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Missing bearer token")
    token = authorization.split(" ", 1)[1]
    try:
        decoded = verify_token(token)
    except Exception:
        raise HTTPException(status_code=401, detail="Invalid or expired token")

    uid = decoded["uid"]
    snap = db.collection("users").document(uid).get()
    if not snap.exists:
        raise HTTPException(status_code=404, detail="User profile not found — registration may be incomplete")

    profile = snap.to_dict()
    profile["uid"] = uid
    return profile


def require_role(role: str):
    def dependency(user: dict = Depends(get_current_user)) -> dict:
        if user.get("role") != role:
            raise HTTPException(status_code=403, detail=f"Requires {role} role")
        return user
    return dependency
