"""Profile photo processing: any uploaded picture becomes a small square JPEG stored with the profile."""
import base64
import io

from PIL import Image, ImageOps, UnidentifiedImageError

from app.photo_check import PhotoError, decode_base64

AVATAR_SIDE = 256
MIN_SIDE = 64


def process_avatar(image_base64: str) -> str:
    raw = decode_base64(image_base64)
    try:
        img = Image.open(io.BytesIO(raw))
        img.load()
    except (UnidentifiedImageError, OSError, ValueError):
        raise PhotoError("That file is not a picture we can use. Please choose a JPG or PNG photo.")
    img = ImageOps.exif_transpose(img).convert("RGB")
    if min(img.size) < MIN_SIDE:
        raise PhotoError("That picture is too small. Please choose a larger photo.")
    img = ImageOps.fit(img, (AVATAR_SIDE, AVATAR_SIDE), Image.LANCZOS, centering=(0.5, 0.4))  # square, slightly favouring faces
    out = io.BytesIO()
    img.save(out, "JPEG", quality=82, optimize=True)
    return base64.b64encode(out.getvalue()).decode()
