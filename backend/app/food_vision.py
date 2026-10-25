"""
AI check that a meal photo really shows food, and roughly the dish that was logged.

Uses the Gemini API (free tier available from Google AI Studio). Configure with:
    GEMINI_API_KEY   your key (if unset, this check is skipped)
    GEMINI_MODEL     optional model override (default: gemini-3.5-flash-lite)

On any API failure the photo is NOT accepted (so the check cannot be bypassed by
taking the service down); the caller turns FoodCheckUnavailable into a retry message.
"""
import base64
import io
import json
import logging
import os
import time
from concurrent.futures import ThreadPoolExecutor, TimeoutError as FutureTimeout

import requests
from typing import Optional

from PIL import Image

logger = logging.getLogger("nutrifit")

# A "lite" model: this is a simple yes/no classification, and lite models answer in about a
# second or two, whereas the larger flash models spend several seconds "thinking" first.
DEFAULT_MODEL = "gemini-3.5-flash-lite"
TIMEOUT_SECONDS = 15
AI_IMAGE_SIDE = 384


_POOL = ThreadPoolExecutor(max_workers=4)


class FoodCheckUnavailable(RuntimeError):
    pass


def is_enabled() -> bool:
    return bool(os.environ.get("GEMINI_API_KEY"))


def _prompt(recipe_name: str) -> str:
    return (
        "You verify meal photos for a nutrition app. Look at the photo and answer in JSON with keys: "
        '"isFood" (true if the photo clearly shows prepared food or a meal on a plate, bowl, container or table; '
        "false for people, screens, documents, scenery, objects, pets, blank or unrelated images), "
        f'"matchesDish" (true if the food is plausibly "{recipe_name}" or a close variation of it), '
        '"confidence" (number 0 to 1 for your overall judgement), '
        '"description" (one short sentence on what you see).'
    )


def _shrink(jpeg_b64: str) -> str:
    """A smaller image uploads and processes faster, and is plenty to recognise a meal."""
    try:
        img = Image.open(io.BytesIO(base64.b64decode(jpeg_b64))).convert("RGB")
        img.thumbnail((AI_IMAGE_SIDE, AI_IMAGE_SIDE))
        buf = io.BytesIO()
        img.save(buf, format="JPEG", quality=65)
        return base64.b64encode(buf.getvalue()).decode()
    except Exception:
        return jpeg_b64


def check_food_photo(jpeg_b64: str, recipe_name: str) -> Optional[dict]:
    """Returns {isFood, matchesDish, confidence, description}, or None when the check is not configured."""
    key = os.environ.get("GEMINI_API_KEY")
    if not key:
        return None
    model = os.environ.get("GEMINI_MODEL", DEFAULT_MODEL)
    jpeg_b64 = _shrink(jpeg_b64)
    url = f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent"
    body = {
        "contents": [{"parts": [
            {"inline_data": {"mime_type": "image/jpeg", "data": jpeg_b64}},
            {"text": _prompt(recipe_name)},
        ]}],
        "generationConfig": {"responseMimeType": "application/json", "temperature": 0},
    }
    def _call() -> dict:
        resp = requests.post(
            url, json=body, timeout=(5, 12),
            headers={"Content-Type": "application/json", "x-goog-api-key": key},
        )
        resp.raise_for_status()
        return resp.json()

    started = time.monotonic()
    try:
        # Hard overall deadline: socket timeouts alone do not cover slow DNS or
        # several failing network routes in a row, which can add up to far more
        # than the nominal timeout.
        future = _POOL.submit(_call)
        payload = future.result(timeout=TIMEOUT_SECONDS)
        text = payload["candidates"][0]["content"]["parts"][0]["text"]
        data = json.loads(text)
        logger.info("Food check (%s) took %.1fs", model, time.monotonic() - started)
        return {
            "isFood": bool(data.get("isFood")),
            "matchesDish": bool(data.get("matchesDish")),
            "confidence": float(data.get("confidence", 0)),
            "description": str(data.get("description", "")),
        }
    except (requests.RequestException, FutureTimeout, KeyError, IndexError, ValueError) as e:
        logger.warning("Food check (%s) failed after %.1fs: %s", model, time.monotonic() - started, repr(e))
        raise FoodCheckUnavailable(repr(e))


def reasons_from_check(result: dict, recipe_name: str) -> list:
    reasons = []
    if not result["isFood"]:
        reasons.append("This doesn't look like a meal. Take a photo of your food.")
    elif not result["matchesDish"]:
        reasons.append(f"This doesn't look like {recipe_name}. Take a photo of the meal you logged.")
    return reasons
