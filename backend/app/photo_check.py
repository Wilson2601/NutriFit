"""
Server-side checks for meal photos.

The mobile app only offers a live camera (never the gallery). This module adds
independent checks on the uploaded file itself: it must be a real, decodable,
non-trivial image that has not been submitted before.

NOTE: this does not do AI food recognition. `verify_photo` is the single place
to plug a vision model in later (e.g. return extra reasons if no food detected).
"""
import base64
import binascii
import hashlib
import io
from typing import List, Optional

from PIL import Image, ImageStat, UnidentifiedImageError

MAX_BYTES = 6 * 1024 * 1024
MIN_SIDE = 240
THUMB_SIDE = 480


class PhotoError(ValueError):
    pass


def decode_base64(data: str) -> bytes:
    if "," in data[:100] and data.strip().startswith("data:"):
        data = data.split(",", 1)[1]
    try:
        raw = base64.b64decode(data, validate=False)
    except (binascii.Error, ValueError):
        raise PhotoError("The photo could not be read. Please retake it.")
    if not raw:
        raise PhotoError("The photo is empty. Please retake it.")
    if len(raw) > MAX_BYTES:
        raise PhotoError("The photo is too large (max 6 MB).")
    return raw


def _average_hash(img: Image.Image) -> str:
    small = img.convert("L").resize((8, 8))
    px = list(small.tobytes())
    avg = sum(px) / len(px)
    return "".join("1" if p >= avg else "0" for p in px)


def hamming(a: str, b: str) -> int:
    return sum(x != y for x, y in zip(a, b))


def verify_photo(raw: bytes, previous_hashes: Optional[List[str]] = None) -> dict:
    """
    Returns {ok, reasons, sha256, ahash, width, height, thumbnailB64}.
    `ok` is False when any check fails; `reasons` explains each failure in plain English.
    """
    previous_hashes = previous_hashes or []
    try:
        img = Image.open(io.BytesIO(raw))
        img.load()
    except (UnidentifiedImageError, OSError):
        raise PhotoError("That file is not a valid photo. Please retake it with the camera.")

    img = img.convert("RGB")
    width, height = img.size
    reasons = []

    if min(width, height) < MIN_SIDE:
        reasons.append("The photo is too small. Move closer and retake it.")

    gray = img.convert("L")
    stat = ImageStat.Stat(gray)
    brightness, spread = stat.mean[0], stat.stddev[0]
    if brightness < 25:
        reasons.append("The photo is too dark. Turn on a light and retake it.")
    elif brightness > 235:
        reasons.append("The photo is overexposed. Avoid direct glare and retake it.")
    if spread < 12:
        reasons.append("The photo looks blank. Point the camera at your meal.")

    sha = hashlib.sha256(raw).hexdigest()
    ahash = _average_hash(img)
    if any(p == sha or (len(p) == 64 and hamming(p, ahash) <= 3) for p in previous_hashes):
        reasons.append("This looks the same as an earlier photo. Take a new photo of this meal.")

    thumb = img.copy()
    thumb.thumbnail((THUMB_SIDE, THUMB_SIDE))
    buf = io.BytesIO()
    thumb.save(buf, format="JPEG", quality=70, optimize=True)

    return {
        "ok": not reasons, "reasons": reasons, "sha256": sha, "ahash": ahash,
        "width": width, "height": height,
        "thumbnailB64": base64.b64encode(buf.getvalue()).decode(),
    }
